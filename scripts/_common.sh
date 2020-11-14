#!/bin/bash

#=================================================
# COMMON VARIABLES
#=================================================

pkg_dependencies="g++ libjemalloc1|libjemalloc2 libjemalloc-dev zlib1g-dev libreadline-dev libpq-dev libssl-dev libyaml-dev libcurl4-openssl-dev libapr1-dev libxslt1-dev libxml2-dev vim imagemagick postgresql postgresql-server-dev-all postgresql-contrib optipng jhead jpegoptim gifsicle brotli"

RUBY_VERSION="2.7.1"

#=================================================
# PERSONAL HELPERS
#=================================================

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
    ynh_die --message="You must have a swap partition in order to install and use this application"
  elif ! is_swappiness_sufficient ; then
    ynh_die --message="Your swappiness must be higher than 50; please see https://en.wikipedia.org/wiki/Swappiness"
  elif ! is_memory_available 1000000 ; then
    ynh_die --message="You must have a minimum of 1Gb available memory (RAM+swap) for the installation"
  fi
}
# Checks discourse upgrade memory requirements
# Less requirements as the software is already installed and running
# terminates upgrade if requirements not met
check_memory_requirements_upgrade() {
  if ! is_memory_available 400000 ; then
    ynh_die --message="You must have a minimum of 400Mb available memory (RAM+swap) for the upgrade"
  fi
}

ynh_maintenance_mode_ON () {
	# Load value of $path_url and $domain from the config if their not set
	if [ -z $path_url ]; then
		path_url=$(ynh_app_setting_get $app path)
	fi
	if [ -z $domain ]; then
		domain=$(ynh_app_setting_get $app domain)
	fi

	# Create an html to serve as maintenance notice
	echo "<!DOCTYPE html>
<html>
<head>
<meta http-equiv="refresh" content="3">
<title>Your app $app is currently under maintenance!</title>
<style>
	body {
		width: 70em;
		margin: 0 auto;
	}
</style>
</head>
<body>
<h1>Your app $app is currently under maintenance!</h1>
<p>This app has been put under maintenance by your administrator at $(date)</p>
<p>Please wait until the maintenance operation is done. This page will be reloaded as soon as your app will be back.</p>

</body>
</html>" > "/var/www/html/maintenance.$app.html"

	# Create a new nginx config file to redirect all access to the app to the maintenance notice instead.
	echo "# All request to the app will be redirected to ${path_url}_maintenance and fall on the maintenance notice
rewrite ^${path_url}/(.*)$ ${path_url}_maintenance/? redirect;
# Use another location, to not be in conflict with the original config file
location ${path_url}_maintenance/ {
alias /var/www/html/ ;

try_files maintenance.$app.html =503;

# Include SSOWAT user panel.
include conf.d/yunohost_panel.conf.inc;
}" > "/etc/nginx/conf.d/$domain.d/maintenance.$app.conf"

	# The current config file will redirect all requests to the root of the app.
	# To keep the full path, we can use the following rewrite rule:
	# 	rewrite ^${path_url}/(.*)$ ${path_url}_maintenance/\$1? redirect;
	# The difference will be in the $1 at the end, which keep the following queries.
	# But, if it works perfectly for a html request, there's an issue with any php files.
	# This files are treated as simple files, and will be downloaded by the browser.
	# Would be really be nice to be able to fix that issue. So that, when the page is reloaded after the maintenance, the user will be redirected to the real page he was.

	systemctl reload nginx
}

ynh_maintenance_mode_OFF () {
	# Load value of $path_url and $domain from the config if their not set
	if [ -z $path_url ]; then
		path_url=$(ynh_app_setting_get $app path)
	fi
	if [ -z $domain ]; then
		domain=$(ynh_app_setting_get $app domain)
	fi

	# Rewrite the nginx config file to redirect from ${path_url}_maintenance to the real url of the app.
	echo "rewrite ^${path_url}_maintenance/(.*)$ ${path_url}/\$1 redirect;" > "/etc/nginx/conf.d/$domain.d/maintenance.$app.conf"
	systemctl reload nginx

	# Sleep 4 seconds to let the browser reload the pages and redirect the user to the app.
	sleep 4

	# Then remove the temporary files used for the maintenance.
	rm "/var/www/html/maintenance.$app.html"
	rm "/etc/nginx/conf.d/$domain.d/maintenance.$app.conf"

	systemctl reload nginx
}

#=================================================
# EXPERIMENTAL HELPERS
#=================================================

#=================================================
# FUTURE OFFICIAL HELPERS
#=================================================

#=================================================
# RUBY HELPER
#=================================================

rbenv_install_dir="/opt/rbenv"
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
  echo "SOURCE_URL=https://github.com/rbenv/rbenv/archive/v1.1.2.tar.gz
SOURCE_SUM=80ad89ffe04c0b481503bd375f05c212bbc7d44ef5f5e649e0acdf25eba86736" > "../conf/rbenv.src"
  # Download and extract rbenv
  ynh_setup_source "$rbenv_install_dir" rbenv

  # Build an app.src for ruby-build
  mkdir -p "../conf"
  echo "SOURCE_URL=https://github.com/rbenv/ruby-build/archive/v20200520.tar.gz
SOURCE_SUM=52be6908a94fbd4a94f5064e8b19d4a3baa4b773269c3884165518d83bcc8922" > "../conf/ruby-build.src"
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
# | arg: -v, --ruby_version= - Version of ruby to install.
#        If possible, prefer to use major version number (e.g. 8 instead of 8.10.0).
#        The crontab will handle the update of minor versions when needed.
ynh_install_ruby () {
  # Declare an array to define the options of this helper.
  declare -Ar args_array=( [v]=ruby_version= )
  # Use rbenv, https://github.com/rbenv/rbenv to manage the ruby versions
  local ruby_version
  # Manage arguments with getopts
  ynh_handle_getopts_args "$@"

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
  elif dpkg --compare-versions "$($rbenv_install_dir/bin/rbenv --version | cut -d" " -f2)" lt "1.1.2"
  then
    ynh_install_rbenv
  elif dpkg --compare-versions "$($rbenv_install_dir/plugins/ruby-build/bin/ruby-build --version | cut -d" " -f2)" lt "20200520"
  then
    ynh_install_rbenv
  fi

  # Restore /usr/local/bin in PATH (if needed)
  PATH=$CLEAR_PATH

  # And replace the old ruby binary
  test -x /usr/bin/ruby_rbenv && mv /usr/bin/ruby_rbenv /usr/bin/ruby

  # Install the requested version of ruby
  CONFIGURE_OPTS="--disable-install-doc --with-jemalloc" MAKE_OPTS="-j2" rbenv install --skip-existing $ruby_version

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

# Returns true if upstream version is up to date
#
# This helper should be used to avoid an upgrade of the upstream version
# when it's not needed (but yet allowing to upgrade other parts of the
# YunoHost application (e.g. nginx conf)
#
# usage: ynh_is_upstream_up_to_date (returns a boolean)
ynh_is_upstream_up_to_date () {
	local version=$(ynh_read_manifest "/etc/yunohost/apps/$YNH_APP_INSTANCE_NAME/manifest.json" "version" || echo 1.0)
  version="${version/~ynh*/}"
	local last_version=$(ynh_read_manifest "../manifest.json" "version" || echo 1.0)
  last_version="${last_version/~ynh*/}"
  [ "$version" = "$last_version" ]
}

#=================================================
# REDIS HELPERS
#=================================================

# get the first available redis database
#
# usage: ynh_redis_get_free_db
# | returns: the database number to use
ynh_redis_get_free_db() {
	local result max db
	result="$(redis-cli INFO keyspace)"

	# get the num
	max=$(cat /etc/redis/redis.conf | grep ^databases | grep -Eow "[0-9]+")

	db=0
	# default Debian setting is 15 databases
	for i in $(seq 0 "$max")
	do
	 	if ! echo "$result" | grep -q "db$i"
	 	then
			db=$i
	 		break 1
 		fi
 		db=-1
	done

	test "$db" -eq -1 && ynh_die --message="No available Redis databases..."

	echo "$db"
}

# Create a master password and set up global settings
# Please always call this script in install and restore scripts
#
# usage: ynh_redis_remove_db database
# | arg: database - the database to erase
ynh_redis_remove_db() {
	local db=$1
	redis-cli -n "$db" flushall
}
