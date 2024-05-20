#!/bin/bash

#=================================================
# COMMON VARIABLES
#=================================================

# dependencies used by the app
#pkg_dependencies="g++ libjemalloc1|libjemalloc2 libjemalloc-dev zlib1g-dev libreadline-dev libpq-dev libssl-dev libyaml-dev libcurl4-dev libapr1-dev libxslt1-dev libxml2-dev vim imagemagick postgresql postgresql-server-dev-all postgresql-contrib optipng jhead jpegoptim gifsicle brotli"
pkg_dependencies="postgresql postgresql-client postgresql-contrib imagemagick libjemalloc1|libjemalloc2"
build_pkg_dependencies="libcurl4-openssl-dev libyaml-dev libxml2-dev libpq-dev libreadline-dev brotli libunwind-dev libtcmalloc-minimal4 cmake pngcrush pngquant advancecomp jhead jpegoptim libjpeg-turbo-progs optipng"

ruby_version="3.0.0"

nodejs_version="16"

#=================================================
# PERSONAL HELPERS
#=================================================

# Execute a command as another user with login
# (hence in user home dir, with prior loading of .profile, etc.)
# usage: exec_login_as USER COMMAND [ARG ...]
exec_login_as() {
  local user=$1
  shift 1
  ynh_exec_as $user --login "$@"
}

# Returns true if a swap partition is enabled, false otherwise
# usage: is_swap_present
is_swap_present() {
  [ $(awk '/^SwapTotal:/{print $2}' /proc/meminfo)  -gt 0 ]
}

# Returns true if swappiness higher than 10
# usage: is_swappiness_sufficient
is_swappiness_sufficient() {
  [ $(cat /proc/sys/vm/swappiness)  -gt 10 ]
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
    ynh_print_warn --message="You must have a swap partition in order to install and use this application"
  elif ! is_swappiness_sufficient ; then
    ynh_print_warn --message="Your swappiness must be higher than 10; please see https://en.wikipedia.org/wiki/Swappiness"
  elif ! is_memory_available 1000000 ; then
    ynh_print_warn --message="You must have a minimum of 1Gb available memory (RAM+swap) for the installation"
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
