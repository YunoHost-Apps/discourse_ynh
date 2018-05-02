#!/bin/bash
#
# Common variables
#

pkg_dependencies="zlib1g-dev libreadline-dev libpq-dev libssl-dev libyaml-dev libcurl4-openssl-dev libapr1-dev libxslt1-dev checkinstall libxml2-dev vim imagemagick postgresql postgresql-server-dev-all postgresql-contrib optipng jhead jpegoptim gifsicle"
RUBY_VERSION="2.4.4"

# Execute a command as another user with login
# (hence in user home dir, with prior loading of .profile, etc.)
# usage: exec_login_as USER COMMAND [ARG ...]
exec_login_as() {
  local user=$1
  shift 1
  exec_as $user --login "$@"
}
# Execute a command as another user
# usage: exec_as USER COMMAND [ARG ...]
exec_as() {
  local user=$1
  shift 1

  if [[ $user = $(whoami) ]]; then
    eval "$@"
  else
    sudo -u "$user" "$@"
  fi
}

# Returns true if a swap partition is enabled, false otherwise
# usage: is_swap_present
is_swap_present() {
  [ $(awk '/^SwapTotal:/{print $2}' /proc/meminfo)  -gt 0 ]
}

# Returns true if swappiness higher than 50
# usage: is_swappiness_sufficient
is_swappiness_sufficient() {
  [ $(cat /proc/sys/vm/swappiness)  -gt 50 ]
}

# Returns true if specified free memory is available (RAM + swap)
# usage: is_memory_available MEMORY (in bytes)
is_memory_available() {
  local needed_memory=$1
  local freemem="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)"
  local freeswap="$(awk '/^SwapFree:/{print $2}' /proc/meminfo)"
  [ $(($freemem+$freeswap)) -gt $needed_memory ]
}

# Checks discourse install memory requirements
# terminates installation if requirements not met
check_memory_requirements() {
  if ! is_swap_present ; then
    ynh_die "You must have a swap partition in order to install and use this application"
  elif ! is_swappiness_sufficient ; then
    ynh_die "Your swappiness must be higher than 50; please see https://en.wikipedia.org/wiki/Swappiness"
  elif ! is_memory_available 1000000 ; then
    ynh_die "You must have a minimum of 1Gb available memory (RAM+swap) for the installation"
  fi
}
# Checks discourse upgrade memory requirements
# Less requirements as the software is already installed and running
# terminates upgrade if requirements not met
check_memory_requirements_upgrade() {
  if ! is_memory_available 400000 ; then
    ynh_die "You must have a minimum of 400Mb available memory (RAM+swap) for the upgrade"
  fi
}
#=================================================
# POSTGRES HELPERS
#=================================================

# Create a master password and set up global settings
# Please always call this script in install and restore scripts
#
# usage: ynh_psql_test_if_first_run

ynh_psql_test_if_first_run() {
	if [ -f /etc/yunohost/psql ];
	then
		echo "PostgreSQL is already installed, no need to create master password"
	else
		pgsql=$(ynh_string_random)
		pg_hba=""
		echo "$pgsql" >> /etc/yunohost/psql

		if [ -e /etc/postgresql/9.4/ ]
		then
			pg_hba=/etc/postgresql/9.4/main/pg_hba.conf
		elif [ -e /etc/postgresql/9.6/ ]
		then
			pg_hba=/etc/postgresql/9.6/main/pg_hba.conf
		else
			ynh_die "postgresql shoud be 9.4 or 9.6"
		fi

		systemctl start postgresql
		sudo --login --user=postgres psql -c"ALTER user postgres WITH PASSWORD '$pgsql'" postgres

		# force all user to connect to local database using passwords
		# https://www.postgresql.org/docs/current/static/auth-pg-hba-conf.html#EXAMPLE-PG-HBA.CONF
		# Note: we can't use peer since YunoHost create users with nologin
		#  See: https://github.com/YunoHost/yunohost/blob/unstable/data/helpers.d/user
		sed -i '/local\s*all\s*all\s*peer/i \
		local all all password' "$pg_hba"
		systemctl enable postgresql
		systemctl reload postgresql
	fi
}

# Open a connection as a user
#
# example: ynh_psql_connect_as 'user' 'pass' <<< "UPDATE ...;"
# example: ynh_psql_connect_as 'user' 'pass' < /path/to/file.sql
#
# usage: ynh_psql_connect_as user pwd [db]
# | arg: user - the user name to connect as
# | arg: pwd - the user password
# | arg: db - the database to connect to
ynh_psql_connect_as() {
	user="$1"
	pwd="$2"
	db="$3"
	sudo --login --user=postgres PGUSER="$user" PGPASSWORD="$pwd" psql "$db"
}

# # Execute a command as root user
#
# usage: ynh_psql_execute_as_root sql [db]
# | arg: sql - the SQL command to execute
# | arg: db - the database to connect to
ynh_psql_execute_as_root () {
	sql="$1"
	sudo --login --user=postgres psql <<< "$sql"
}

# Execute a command from a file as root user
#
# usage: ynh_psql_execute_file_as_root file [db]
# | arg: file - the file containing SQL commands
# | arg: db - the database to connect to
ynh_psql_execute_file_as_root() {
	file="$1"
	db="$2"
	sudo --login --user=postgres psql "$db" < "$file"
}

# Create a database, an user and its password. Then store the password in the app's config
#
# After executing this helper, the password of the created database will be available in $db_pwd
# It will also be stored as "psqlpwd" into the app settings.
#
# usage: ynh_psql_setup_db user name [pwd]
# | arg: user - Owner of the database
# | arg: name - Name of the database
# | arg: pwd - Password of the database. If not given, a password will be generated
ynh_psql_setup_db () {
	db_user="$1"
	app="$1"
	db_name="$2"
	new_db_pwd=$(ynh_string_random)	# Generate a random password
	# If $3 is not given, use new_db_pwd instead for db_pwd.
	db_pwd="${3:-$new_db_pwd}"
	ynh_psql_create_db "$db_name" "$db_user" "$db_pwd"	# Create the database
	ynh_app_setting_set "$app" psqlpwd "$db_pwd"	# Store the password in the app's config
}

# Create a database and grant privilegies to a user
#
# usage: ynh_psql_create_db db [user [pwd]]
# | arg: db - the database name to create
# | arg: user - the user to grant privilegies
# | arg: pwd  - the user password
ynh_psql_create_db() {
	db="$1"
	user="$2"
	pwd="$3"
	ynh_psql_create_user "$user" "$pwd"
	sudo --login --user=postgres createdb --owner="$user" "$db"
}

# Drop a database
#
# usage: ynh_psql_drop_db db
# | arg: db - the database name to drop
# | arg: user - the user to drop
ynh_psql_remove_db() {
	db="$1"
	user="$2"
	sudo --login --user=postgres dropdb "$db"
	ynh_psql_drop_user "$user"
}

# Dump a database
#
# example: ynh_psql_dump_db 'roundcube' > ./dump.sql
#
# usage: ynh_psql_dump_db db
# | arg: db - the database name to dump
# | ret: the psqldump output
ynh_psql_dump_db() {
	db="$1"
	sudo --login --user=postgres pg_dump "$db"
}


# Create a user
#
# usage: ynh_psql_create_user user pwd [host]
# | arg: user - the user name to create
ynh_psql_create_user() {
	user="$1"
	pwd="$2"
        sudo --login --user=postgres psql -c"CREATE USER $user WITH PASSWORD '$pwd'" postgres
}

# Drop a user
#
# usage: ynh_psql_drop_user user
# | arg: user - the user name to drop
ynh_psql_drop_user() {
	user="$1"
	sudo --login --user=postgres dropuser "$user"
}

# ============= MODIFIED EXISTING YUNOHOST HELPERS =============

# Create a dedicated systemd config
#
# usage: ynh_add_systemd_config [service] [template]
# | arg: service - Service name (optionnal, $app by default)
# | arg: template - Name of template file (optionnal, this is 'systemd' by default, meaning ./conf/systemd.service will be used as template)
#
# This will use the template ../conf/<templatename>.service
# to generate a systemd config, by replacing the following keywords
# with global variables that should be defined before calling
# this helper :
#
#   __APP__       by  $app
#   __FINALPATH__ by  $final_path
#
ynh_add_systemd_config () {
	local service_name="${1:-$app}"

	finalsystemdconf="/etc/systemd/system/$service_name.service"
	ynh_backup_if_checksum_is_different "$finalsystemdconf"
	sudo cp ../conf/${2:-systemd.service} "$finalsystemdconf"

	# To avoid a break by set -u, use a void substitution ${var:-}. If the variable is not set, it's simply set with an empty variable.
	# Substitute in a nginx config file only if the variable is not empty
	if test -n "${final_path:-}"; then
		ynh_replace_string "__FINALPATH__" "$final_path" "$finalsystemdconf"
	fi
	if test -n "${app:-}"; then
		ynh_replace_string "__APP__" "$app" "$finalsystemdconf"
	fi
	ynh_store_file_checksum "$finalsystemdconf"

	sudo chown root: "$finalsystemdconf"
	sudo systemctl enable $service_name
	sudo systemctl daemon-reload
}

# Remove the dedicated systemd config
#
# usage: ynh_remove_systemd_config [service]
# | arg: service - Service name (optionnal, $app by default)
#
ynh_remove_systemd_config () {
	local service_name="${1:-$app}"

	local finalsystemdconf="/etc/systemd/system/$service_name.service"
	if [ -e "$finalsystemdconf" ]; then
		sudo systemctl stop $service_name
		sudo systemctl disable $service_name
		ynh_secure_remove "$finalsystemdconf"
		sudo systemctl daemon-reload
	fi
}

# Create a system user
#
# usage: ynh_system_user_create user_name [home_dir] [use_shell]
# | arg: user_name - Name of the system user that will be create
# | arg: home_dir - Path of the home dir for the user. Usually the final path of the app. If this argument is omitted, the user will be created without home
# | arg: use_shell - Create a user using the default shell if present. If this argument is omitted, the user will be created with /usr/sbin/nologin shell
ynh_system_user_create () {
	if ! ynh_system_user_exists "$1"	# Check if the user exists on the system
	then	# If the user doesn't exist
		if [ $# -ge 2 ]; then	# If a home dir is mentioned
			local user_home_dir="-d $2"
		else
			local user_home_dir="--no-create-home"
		fi
    if [ $# -ge 3 ]; then	# If we want a shell for the user
      local shell="" # Use default shell
		else
			local shell="--shell /usr/sbin/nologin"
		fi
		useradd $user_home_dir --system --user-group $1 $shell || ynh_die "Unable to create $1 system account"
	fi
}

# ============= FUTURE YUNOHOST HELPERS =============

# Create a dedicated fail2ban config (jail and filter conf files)
#
# usage: ynh_add_fail2ban_config log_file filter [max_retry [ports]]
# | arg: log_file - Log file to be checked by fail2ban
# | arg: failregex - Failregex to be looked for by fail2ban
# | arg: max_retry - Maximum number of retries allowed before banning IP address - default: 3
# | arg: ports - Ports blocked for a banned IP address - default: http,https
ynh_add_fail2ban_config () {
   # Process parameters
   logpath=$1
   failregex=$2
   max_retry=${3:-3}
   ports=${4:-http,https}

  test -n "$logpath" || ynh_die "ynh_add_fail2ban_config expects a logfile path as first argument and received nothing."
  test -n "$failregex" || ynh_die "ynh_add_fail2ban_config expects a failure regex as second argument and received nothing."

	finalfail2banjailconf="/etc/fail2ban/jail.d/$app.conf"
	finalfail2banfilterconf="/etc/fail2ban/filter.d/$app.conf"
	ynh_backup_if_checksum_is_different "$finalfail2banjailconf" 1
	ynh_backup_if_checksum_is_different "$finalfail2banfilterconf" 1

  cat > $finalfail2banjailconf <<EOF
[$app]
enabled = true
port = $ports
filter = $app
logpath = $logpath
maxretry = $max_retry
EOF

  cat > $finalfail2banfilterconf <<EOF
[INCLUDES]
before = common.conf
[Definition]
failregex = $failregex
ignoreregex =
EOF

	ynh_store_file_checksum "$finalfail2banjailconf"
	ynh_store_file_checksum "$finalfail2banfilterconf"

  systemctl restart fail2ban
  local fail2ban_error="$(journalctl -u fail2ban | tail -n50 | grep "WARNING.*$app.*")"
  if [ -n "$fail2ban_error" ]
  then
    echo "[ERR] Fail2ban failed to load the jail for $app" >&2
    echo "WARNING${fail2ban_error#*WARNING}" >&2
  fi
}

# Remove the dedicated fail2ban config (jail and filter conf files)
#
# usage: ynh_remove_fail2ban_config
ynh_remove_fail2ban_config () {
	ynh_secure_remove "/etc/fail2ban/jail.d/$app.conf"
  ynh_secure_remove "/etc/fail2ban/filter.d/$app.conf"
	systemctl restart fail2ban
}

# Delete a file checksum from the app settings
#
# $app should be defined when calling this helper
#
# usage: ynh_remove_file_checksum file
# | arg: file - The file for which the checksum will be deleted
ynh_delete_file_checksum () {
	local checksum_setting_name=checksum_${1//[\/ ]/_}	# Replace all '/' and ' ' by '_'
	ynh_app_setting_delete $app $checksum_setting_name
}


ynh_clean_check_starting_systemd () {
  # Stop the execution of tail.
  kill -s 15 $pid_tail 2>&1
  ynh_secure_remove "$templog" 2>&1
}

# Start or restart a service and follow its booting
#
# usage: ynh_check_starting_systemd "Line to match" [Service name] [Timeout]
#
# | arg: Line to match - The line to find in the log to attest the service have finished to boot.
# | arg: Service name
# | arg: Timeout - The maximum time to wait before ending the watching. Defaut 300 seconds.
ynh_check_starting_systemd () {
	local line_to_match="$1"
	local service_name="${2:-$app}"
	local timeout=${3:-300}



	echo "Starting of $service_name" >&2
	systemctl stop $service_name
	local templog="$(mktemp)"
	# Follow the starting of the app in its log
	journalctl -u $service_name -f > "$templog" &
	# Get the PID of the tail command
	local pid_tail=$!
	systemctl start $service_name

	local i=0
	for i in `seq 1 $timeout`
	do
		# Read the log until the sentence is found, that means the app finished starting. Or run until the timeout
		if grep --quiet "$line_to_match" "$templog"
		then
			echo "The service $service_name has correctly started." >&2
			break
		fi
		echo -n "." >&2
		sleep 1
	done
	if [ $i -eq $timeout ]
	then
		echo "The service $service_name didn't fully started before the timeout." >&2
	fi

	echo ""
	ynh_clean_check_starting_systemd
}


rbenv_install_dir="/opt/rbenv"
ruby_version_path="/opt/rbenv/versions"
# RBENV_ROOT is the directory of rbenv, it needs to be loaded as a environment variable.
export RBENV_ROOT="$rbenv_install_dir"

# Install ruby version management
#
# [internal]
#
# usage: ynh_install_rbenv
ynh_install_rbenv () {
	echo "Installation of rbenv - ruby version management" >&2
	# Build an app.src for rbenv
	mkdir -p "../conf"
	echo "SOURCE_URL=https://github.com/rbenv/rbenv/archive/v1.1.1.tar.gz
SOURCE_SUM=41f1a60714c55eceb21d692a469aee1ec4f46bba351d0dfcb0c660ff9cf1a1c9" > "../conf/rbenv.src"
	# Download and extract rbenv
	ynh_setup_source "$rbenv_install_dir" rbenv

  # Build an app.src for ruby-build
  mkdir -p "../conf"
  echo "SOURCE_URL=https://github.com/rbenv/ruby-build/archive/v20180329.tar.gz
SOURCE_SUM=4c8610c178ef2fa6bb29d4bcfca52608914632a51a56a5e70aeec8bf0894167b" > "../conf/ruby-build.src"
  # Download and extract ruby-build
  ynh_setup_source "$rbenv_install_dir/plugins/ruby-build" ruby-build

  (cd $rbenv_install_dir
  ./src/configure && make -C src)

# Create shims directory if needed
if [ ! -d $rbenv_install_dir/shims ] ; then
  mkdir $rbenv_install_dir/shims
fi
}

# Install a specific version of ruby
#
# ynh_install_ruby will install the version of ruby provided as argument by using rbenv.
#
# rbenv (ruby version management) stores the target ruby version in a .ruby_version file created in the target folder (using rbenv local <version>)
# It then uses that information for every ruby user that uses rbenv provided ruby command
#
# This helper creates a /etc/profile.d/rbenv.sh that configures PATH environment for rbenv
# for every LOGIN user, hence your user must have a defined shell (as opposed to /usr/sbin/nologin)
#
# Don't forget to execute ruby-dependent command in a login environment
# (e.g. sudo --login option)
# When not possible (e.g. in systemd service definition), please use direct path
# to rbenv shims (e.g. $RBENV_ROOT/shims/bundle)
#
# usage: ynh_install_ruby ruby_version user
# | arg: ruby_version - Version of ruby to install.
#        If possible, prefer to use major version number (e.g. 8 instead of 8.10.0).
#        The crontab will handle the update of minor versions when needed.
ynh_install_ruby () {
	# Use rbenv, https://github.com/rbenv/rbenv to manage the ruby versions
	local ruby_version="$1"

	# Create $rbenv_install_dir
	mkdir -p "$rbenv_install_dir/plugins/ruby-build"

	# Load rbenv path in PATH
	CLEAR_PATH="$rbenv_install_dir/bin:$PATH"

	# Remove /usr/local/bin in PATH in case of ruby prior installation
	PATH=$(echo $CLEAR_PATH | sed 's@/usr/local/bin:@@')

	# Move an existing ruby binary, to avoid to block rbenv
	test -x /usr/bin/ruby && mv /usr/bin/ruby /usr/bin/ruby_rbenv

	# If rbenv is not previously setup, install it
	if ! type rbenv > /dev/null 2>&1
	then
		ynh_install_rbenv
	fi

	# Restore /usr/local/bin in PATH (if needed)
	PATH=$CLEAR_PATH

	# And replace the old ruby binary
	test -x /usr/bin/ruby_rbenv && mv /usr/bin/ruby_rbenv /usr/bin/ruby

	# Install the requested version of ruby
	CONFIGURE_OPTS="--disable-install-doc" MAKE_OPTS="-j2" rbenv install --skip-existing $ruby_version

	# Store the ID of this app and the version of ruby requested for it
	echo "$YNH_APP_ID:$ruby_version" | tee --append "$rbenv_install_dir/ynh_app_version"

	# Store ruby_version into the config of this app
	ynh_app_setting_set $app ruby_version $ruby_version

  # Set environment for ruby users
  echo  "#rbenv
export RBENV_ROOT=$rbenv_install_dir
export PATH=\"$rbenv_install_dir/bin:$PATH\"
eval \"\$(rbenv init -)\"
#rbenv" > /etc/profile.d/rbenv.sh

  # Load the right environment for the Installation
  eval "$(rbenv init -)"

  (cd $final_path
  rbenv local $ruby_version)
}

# Remove the version of ruby used by the app.
#
# This helper will check if another app uses the same version of ruby,
# if not, this version of ruby will be removed.
# If no other app uses ruby, rbenv will be also removed.
#
# usage: ynh_remove_ruby
ynh_remove_ruby () {
	ruby_version=$(ynh_app_setting_get $app ruby_version)

	# Remove the line for this app
	sed --in-place "/$YNH_APP_ID:$ruby_version/d" "$rbenv_install_dir/ynh_app_version"

	# If no other app uses this version of ruby, remove it.
	if ! grep --quiet "$ruby_version" "$rbenv_install_dir/ynh_app_version"
	then
		$rbenv_install_dir/bin/rbenv uninstall --force $ruby_version
	fi

  # Remove rbenv environment configuration
  rm /etc/profile.d/rbenv.sh

	# If no other app uses rbenv, remove rbenv and dedicated group
	if [ ! -s "$rbenv_install_dir/ynh_app_version" ]
	then
		ynh_secure_remove "$rbenv_install_dir"
	fi
}

# ============= EXPERIMENTAL HELPERS =============

# Returns true if upstream version is up to date
#
# This helper should be used to avoid an upgrade of the upstream version
# when it's not needed (but yet allowing to upgrade other part of the
# YunoHost application (e.g. nginx conf)
#
# usage: ynh_is_upstream_up_to_date
ynh_is_upstream_up_to_date () {
	local version=$(ynh_read_manifest "/etc/yunohost/apps/$YNH_APP_INSTANCE_NAME/manifest.json" "version" || echo 1.0)
  version="${version/~ynh*/}"
	local last_version=$(ynh_read_manifest "../manifest.json" "version" || echo 1.0)
  last_version="${last_version/~ynh*/}"
  [ "$version" = "$last_version" ]
}

# Read the value of a key in a ynh manifest file
#
# usage: ynh_read_manifest manifest key
# | arg: manifest - Path of the manifest to read
# | arg: key - Name of the key to find
ynh_read_manifest () {
	manifest="$1"
	key="$2"
	python3 -c "import sys, json;print(json.load(open('$manifest', encoding='utf-8'))['$key'])"
}

# Read the upstream version from the manifest
# The version number in the manifest is defined by <upstreamversion>~ynh<packageversion>
# For example : 4.3-2~ynh3
# This include the number before ~ynh
# In the last example it return 4.3-2
#
# usage: ynh_app_upstream_version
ynh_app_upstream_version () {
    manifest_path="../manifest.json"
    if [ ! -e "$manifest_path" ]; then
        manifest_path="../settings/manifest.json"	# Into the restore script, the manifest is not at the same place
    fi
    version_key=$(ynh_read_manifest "$manifest_path" "version")
    echo "${version_key/~ynh*/}"
}

# Read package version from the manifest
# The version number in the manifest is defined by <upstreamversion>~ynh<packageversion>
# For example : 4.3-2~ynh3
# This include the number after ~ynh
# In the last example it return 3
#
# usage: ynh_app_package_version
ynh_app_package_version () {
    manifest_path="../manifest.json"
    if [ ! -e "$manifest_path" ]; then
        manifest_path="../settings/manifest.json"	# Into the restore script, the manifest is not at the same place
    fi
    version_key=$(ynh_read_manifest "$manifest_path" "version")
    echo "${version_key/*~ynh/}"
}
