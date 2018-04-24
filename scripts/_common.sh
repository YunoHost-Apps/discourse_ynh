#!/bin/bash
#
# Common variables
#

pkg_dependencies="ruby-zip libssl-dev libyaml-dev libcurl4-openssl-dev ruby gem libapr1-dev libxslt1-dev checkinstall libxml2-dev ruby-dev vim libmagickwand-dev imagemagick postgresql postgresql-server-dev-all"

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

#=================================================
# POSTGRES HELPERS
#=================================================

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
                su --command="psql -c\"ALTER user postgres WITH PASSWORD '${pgsql}'\"" postgres
		# we can't use peer since YunoHost create users with nologin
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
	su --command="PGUSER=\"${user}\" PGPASSWORD=\"${pwd}\" psql \"${db}\"" postgres
}

# # Execute a command as root user
#
# usage: ynh_psql_execute_as_root sql [db]
# | arg: sql - the SQL command to execute
# | arg: db - the database to connect to
ynh_psql_execute_as_root () {
	sql="$1"
	su --command="psql" postgres <<< "$sql"
}

# Execute a command from a file as root user
#
# usage: ynh_psql_execute_file_as_root file [db]
# | arg: file - the file containing SQL commands
# | arg: db - the database to connect to
ynh_psql_execute_file_as_root() {
	file="$1"
	db="$2"
	su -c "psql $db" postgres < "$file"
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

# Create a database and grant optionnaly privilegies to a user
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
	su --command="createdb --owner=\"${user}\" \"${db}\"" postgres
}

# Drop a database
#
# usage: ynh_psql_drop_db db
# | arg: db - the database name to drop
# | arg: user - the user to drop
ynh_psql_remove_db() {
	db="$1"
	user="$2"
  # Force disconnections from the database (https://dba.stackexchange.com/a/11895)
  ynh_psql_execute_as_root "UPDATE pg_database SET datallowconn = 'false' WHERE datname = '${db}';"
  ynh_psql_execute_as_root "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${db}';"

	su --command="dropdb \"${db}\"" postgres
	ynh_psql_drop_user "${user}"
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
	su --command="pg_dump \"${db}\"" postgres
}


# Create a user
#
# usage: ynh_psql_create_user user pwd [host]
# | arg: user - the user name to create
ynh_psql_create_user() {
	user="$1"
	pwd="$2"
        su --command="psql -c\"CREATE USER ${user} WITH PASSWORD '${pwd}'\"" postgres
}

# Drop a user
#
# usage: ynh_psql_drop_user user
# | arg: user - the user name to drop
ynh_psql_drop_user() {
	user="$1"
	su --command="dropuser \"${user}\"" postgres
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
