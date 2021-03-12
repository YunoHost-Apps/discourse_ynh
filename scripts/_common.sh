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

ynh_ruby_try_bash_extension() {
  if [ -x src/configure ]; then
    src/configure && make -C src || {
      echo "Optional bash extension failed to build, but things will still work normally."
    }
  fi
}

rbenv_install_dir="/opt/rbenv"
ruby_version_path="$rbenv_install_dir/versions"
# RBENV_ROOT is the directory of rbenv, it needs to be loaded as a environment variable.
export RBENV_ROOT="$rbenv_install_dir"

# Load the version of Ruby for an app, and set variables.
#
# ynh_use_ruby has to be used in any app scripts before using Ruby for the first time.
# This helper will provide alias and variables to use in your scripts.
#
# To use gem or Ruby, use the alias `ynh_gem` and `ynh_ruby`
# Those alias will use the correct version installed for the app
# For example: use `ynh_gem install` instead of `gem install`
#
# With `sudo` or `ynh_exec_as`, use instead the fallback variables `$ynh_gem` and `$ynh_ruby`
# And propagate $PATH to sudo with $ynh_ruby_load_path
# Exemple: `ynh_exec_as $app $ynh_ruby_load_path $ynh_gem install`
#
# $PATH contains the path of the requested version of Ruby.
# However, $PATH is duplicated into $ruby_path to outlast any manipulation of $PATH
# You can use the variable `$ynh_ruby_load_path` to quickly load your Ruby version
#  in $PATH for an usage into a separate script.
# Exemple: $ynh_ruby_load_path $final_path/script_that_use_gem.sh`
#
#
# Finally, to start a Ruby service with the correct version, 2 solutions
#  Either the app is dependent of Ruby or gem, but does not called it directly.
#  In such situation, you need to load PATH
#    `Environment="__YNH_RUBY_LOAD_ENV_PATH__"`
#    `ExecStart=__FINALPATH__/my_app`
#     You will replace __YNH_RUBY_LOAD_ENV_PATH__ with $ynh_ruby_load_path
#
#  Or Ruby start the app directly, then you don't need to load the PATH variable
#    `ExecStart=__YNH_RUBY__ my_app run`
#     You will replace __YNH_RUBY__ with $ynh_ruby
#
#
# one other variable is also available
#   - $ruby_path: The absolute path to Ruby binaries for the chosen version.
#
# usage: ynh_use_ruby
#
# Requires YunoHost version 2.7.12 or higher.
ynh_use_ruby () {
    ruby_version=$(ynh_app_setting_get --app=$app --key=ruby_version)

    # Get the absolute path of this version of Ruby
    ruby_path="$ruby_version_path/$YNH_APP_INSTANCE_NAME/bin"

    # Allow alias to be used into bash script
    shopt -s expand_aliases

    # Create an alias for the specific version of Ruby and a variable as fallback
    ynh_ruby="$ruby_path/ruby"
    alias ynh_ruby="$ynh_ruby"
    # And gem
    ynh_gem="$ruby_path/gem"
    alias ynh_gem="$ynh_gem"

    # Load the path of this version of Ruby in $PATH
    if [[ :$PATH: != *":$ruby_path"* ]]; then
        PATH="$ruby_path:$PATH"
    fi
    # Create an alias to easily load the PATH
    ynh_ruby_load_path="PATH=$PATH"

    # Sets the local application-specific Ruby version
    pushd $final_path
        $rbenv_install_dir/bin/rbenv local $ruby_version
    popd
}

# Install a specific version of Ruby
#
# ynh_install_ruby will install the version of Ruby provided as argument by using rbenv.
#
# rbenv (Ruby Version Management) stores the target Ruby version in a .ruby_version file created in the target folder (using rbenv local <version>)
# It then uses that information for every Ruby user that uses rbenv provided Ruby command
#
# This helper creates a /etc/profile.d/rbenv.sh that configures PATH environment for rbenv
# for every LOGIN user, hence your user must have a defined shell (as opposed to /usr/sbin/nologin)
#
# Don't forget to execute ruby-dependent command in a login environment
# (e.g. sudo --login option)
# When not possible (e.g. in systemd service definition), please use direct path
# to rbenv shims (e.g. $RBENV_ROOT/shims/bundle)
#
# usage: ynh_install_ruby --ruby_version=ruby_version
# | arg: -v, --ruby_version= - Version of ruby to install.
#
# Requires YunoHost version 2.7.12 or higher.
ynh_install_ruby () {
    # Declare an array to define the options of this helper.
    local legacy_args=v
    local -A args_array=( [v]=ruby_version= )
    local ruby_version
    # Manage arguments with getopts
    ynh_handle_getopts_args "$@"

    # Load rbenv path in PATH
    local CLEAR_PATH="$rbenv_install_dir/bin:$PATH"

    # Remove /usr/local/bin in PATH in case of Ruby prior installation
    PATH=$(echo $CLEAR_PATH | sed 's@/usr/local/bin:@@')

    # Move an existing Ruby binary, to avoid to block rbenv
    test -x /usr/bin/ruby && mv /usr/bin/ruby /usr/bin/ruby_rbenv

    # Instal or update rbenv
    rbenv="$(command -v rbenv $rbenv_install_dir/bin/rbenv | head -1)"
    if [ -n "$rbenv" ]; then
        ynh_print_info --message="rbenv already seems installed in \`$rbenv'."
        pushd "${rbenv%/*/*}"
            if git remote -v 2>/dev/null | grep -q rbenv; then
                echo "Trying to update with git..."
                git pull -q --tags origin master
                cd ..
                ynh_ruby_try_bash_extension
            fi
        popd
    else
        ynh_print_info --message="Installing rbenv with git..."
        mkdir -p $rbenv_install_dir
        pushd $rbenv_install_dir
            git init -q
            git remote add -f -t master origin https://github.com/rbenv/rbenv.git > /dev/null 2>&1
            git checkout -q -b master origin/master
            ynh_ruby_try_bash_extension
            rbenv=$rbenv_install_dir/bin/rbenv
        popd
    fi

    ruby_build="$(command -v "$rbenv_install_dir"/plugins/*/bin/rbenv-install rbenv-install | head -1)"
    if [ -n "$ruby_build" ]; then
        ynh_print_info --message="\`rbenv install' command already available in \`$ruby_build'."
        pushd "${ruby_build%/*/*}"
            if git remote -v 2>/dev/null | grep -q ruby-build; then
                ynh_print_info --message="Trying to update rbenv with git..."
                git pull -q origin master
            fi
        popd
    else
        ynh_print_info --message="Installing ruby-build with git..."
        mkdir -p "${rbenv_install_dir}/plugins"
        git clone -q https://github.com/rbenv/ruby-build.git "${rbenv_install_dir}/plugins/ruby-build"
    fi

    rb_alias="$(command -v "$rbenv_install_dir"/plugins/*/bin/rbenv-alias rbenv-alias | head -1)"
    if [ -n "$rb_alias" ]; then
        ynh_print_info --message="\`rbenv alias' command already available in \`$rb_alias'."
        pushd "${rb_alias%/*/*}"
            if git remote -v 2>/dev/null | grep -q rbenv-aliases; then
                ynh_print_info --message="Trying to update rbenv-aliases with git..."
                git pull -q origin master
            fi
        popd
    else
        ynh_print_info --message="Installing rbenv-aliases with git..."
        mkdir -p "${rbenv_install_dir}/plugins"
        git clone -q https://github.com/tpope/rbenv-aliases.git "${rbenv_install_dir}/plugins/rbenv-aliase"
    fi

    rb_latest="$(command -v "$rbenv_install_dir"/plugins/*/bin/rbenv-latest rbenv-latest | head -1)"
    if [ -n "$rb_latest" ]; then
        ynh_print_info --message="\`rbenv latest' command already available in \`$rb_latest'."
        pushd "${rb_latest%/*/*}"
            if git remote -v 2>/dev/null | grep -q xxenv-latest; then
                ynh_print_info --message="Trying to update xxenv-latest with git..."
                git pull -q origin master
            fi
        popd
    else
        ynh_print_info --message="Installing xxenv-latest with git..."
        mkdir -p "${rbenv_install_dir}/plugins"
        git clone -q https://github.com/momo-lab/xxenv-latest.git "${rbenv_install_dir}/plugins/xxenv-latest"
    fi

    # Enable caching
    mkdir -p "${rbenv_install_dir}/cache"

    # Create shims directory if needed
    mkdir -p "${rbenv_install_dir}/shims"

    # Restore /usr/local/bin in PATH
    PATH=$CLEAR_PATH

    # And replace the old Ruby binary
    test -x /usr/bin/ruby_rbenv && mv /usr/bin/ruby_rbenv /usr/bin/ruby

    # Install the requested version of Ruby
    local final_ruby_version=$(rbenv latest --print $ruby_version)
    ynh_print_info --message="Installing Ruby-$final_ruby_version"
    CONFIGURE_OPTS="--disable-install-doc --with-jemalloc" MAKE_OPTS="-j2" rbenv install --skip-existing $final_ruby_version > /dev/null 2>&1

    # Store ruby_version into the config of this app
    ynh_app_setting_set --app=$YNH_APP_INSTANCE_NAME --key=ruby_version --value=$final_ruby_version

    # Remove app virtualenv
    if  `rbenv alias --list | grep --quiet "$YNH_APP_INSTANCE_NAME " 1>/dev/null 2>&1`
    then
        rbenv alias $YNH_APP_INSTANCE_NAME --remove
    fi

    # Create app virtualenv
    rbenv alias $YNH_APP_INSTANCE_NAME $final_ruby_version

    # Cleanup Ruby versions
    ynh_cleanup_ruby

    # Set environment for Ruby users
    echo  "#rbenv
export RBENV_ROOT=$rbenv_install_dir
export PATH=\"$rbenv_install_dir/bin:$PATH\"
eval \"\$(rbenv init -)\"
    #rbenv" > /etc/profile.d/rbenv.sh

    # Load the environment
    eval "$(rbenv init -)"
}

# Remove the version of Ruby used by the app.
#
# This helper will also cleanup Ruby versions
#
# usage: ynh_remove_ruby
ynh_remove_ruby () {
    local ruby_version=$(ynh_app_setting_get --app=$YNH_APP_INSTANCE_NAME --key=ruby_version)

    # Load rbenv path in PATH
    local CLEAR_PATH="$rbenv_install_dir/bin:$PATH"

    # Remove /usr/local/bin in PATH in case of Ruby prior installation
    PATH=$(echo $CLEAR_PATH | sed 's@/usr/local/bin:@@')

    rbenv alias $YNH_APP_INSTANCE_NAME --remove

    # Remove the line for this app
    ynh_app_setting_delete --app=$YNH_APP_INSTANCE_NAME --key=ruby_version

    # Cleanup Ruby versions
    ynh_cleanup_ruby
}

# Remove no more needed versions of Ruby used by the app.
#
# This helper will check what Ruby version are no more required,
# and uninstall them
# If no app uses Ruby, rbenv will be also removed.
#
# usage: ynh_cleanup_ruby
ynh_cleanup_ruby () {

    # List required Ruby versions
    local installed_apps=$(yunohost app list | grep -oP 'id: \K.*$')
    local required_ruby_versions=""
    for installed_app in $installed_apps
    do
        local installed_app_ruby_version=$(yunohost app setting $installed_app ruby_version)
        if [[ $installed_app_ruby_version ]]
        then
            required_ruby_versions="${installed_app_ruby_version}\n${required_ruby_versions}"
        fi
    done
    
    # Remove no more needed Ruby versions
    local installed_ruby_versions=$(rbenv versions --bare --skip-aliases | grep -Ev '/')
    for installed_ruby_version in $installed_ruby_versions
    do
        if ! `echo ${required_ruby_versions} | grep "${installed_ruby_version}" 1>/dev/null 2>&1`
        then
            ynh_print_info --message="Removing of Ruby-$installed_ruby_version"
            $rbenv_install_dir/bin/rbenv uninstall --force $installed_ruby_version
        fi
    done

    # If none Ruby version is required
    if [[ ! $required_ruby_versions ]]
    then
        # Remove rbenv environment configuration
        ynh_print_info --message="Removing of rbenv-$rbenv_version"
        ynh_secure_remove --file="$rbenv_install_dir"
        ynh_secure_remove --file="/etc/profile.d/rbenv.sh"
    fi
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
