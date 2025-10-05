#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================

libjemalloc="$(ldconfig -p | grep libjemalloc | awk 'END {print $NF}')"

_exec_as_app_with_ruby_node() {
    ynh_exec_as_app env PATH="$path_with_nodejs:$path_with_ruby:$PATH" "$@"
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
        ynh_print_warn "You must have a swap partition in order to install and use this application"
    elif ! is_swappiness_sufficient ; then
        ynh_print_warn "Your swappiness must be higher than 10; please see https://en.wikipedia.org/wiki/Swappiness"
    elif ! is_memory_available 1000000 ; then
        ynh_print_warn "You must have a minimum of 1Gb available memory (RAM+swap) for the installation"
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

tools_prefix="$install_dir/dependencies"

install_imagemagick() {
    # See https://github.com/discourse/discourse_docker/blob/main/image/base/install-imagemagick
    ynh_setup_source --source_id="imagemagickv7" --dest_dir="$install_dir/imagemagick_source"
    mkdir -p "$tools_prefix"
    chown -R "$app:$app" "$install_dir/imagemagick_source" "$tools_prefix"

    pushd "$install_dir/imagemagick_source"
        ynh_exec_as_app CFLAGS="-O2 -I$tools_prefix/include -Wno-deprecated-declarations" \
            ./configure \
            --prefix="$tools_prefix" \
            --enable-static \
            --enable-bounds-checking \
            --enable-hdri \
            --enable-hugepages \
            --with-threads \
            --with-modules \
            --with-quantum-depth=16 \
            --without-magick-plus-plus \
            --with-bzlib \
            --with-zlib \
            --without-autotrace \
            --with-freetype \
            --with-jpeg \
            --without-lcms \
            --with-lzma \
            --with-png \
            --with-tiff \
            --with-heic \
            --with-rsvg \
            --with-webp
        ynh_exec_as_app make all -j"$(nproc)"
        ynh_exec_as_app LIBTOOLFLAGS=-Wnone make install
    popd
    ynh_safe_rm "$install_dir/imagemagick_source"
}

install_oxipng() {
    ynh_setup_source --source_id="oxipng" --dest_dir="$install_dir/oxipng_source"
    mkdir -p "$tools_prefix/bin"
    mv "$install_dir/oxipng_source/oxipng" "$tools_prefix/bin/oxipng"
    ynh_safe_rm "$install_dir/oxipng_source"
}

ynh_maintenance_mode_ON () {
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
    echo "# All request to the app will be redirected to ${path}_maintenance and fall on the maintenance notice
rewrite ^${path}/(.*)$ ${path}_maintenance/? redirect;
# Use another location, to not be in conflict with the original config file
location ${path}_maintenance/ {
alias /var/www/html/ ;

try_files maintenance.$app.html =503;

# Include SSOWAT user panel.
include conf.d/yunohost_panel.conf.inc;
}" > "/etc/nginx/conf.d/$domain.d/maintenance.$app.conf"

    # The current config file will redirect all requests to the root of the app.
    # To keep the full path, we can use the following rewrite rule:
    #     rewrite ^${path}/(.*)$ ${path}_maintenance/\$1? redirect;
    # The difference will be in the $1 at the end, which keep the following queries.
    # But, if it works perfectly for a html request, there's an issue with any php files.
    # This files are treated as simple files, and will be downloaded by the browser.
    # Would be really be nice to be able to fix that issue. So that, when the page is reloaded after the maintenance, the user will be redirected to the real page he was.

    systemctl reload nginx
}

ynh_maintenance_mode_OFF () {
    # Rewrite the nginx config file to redirect from ${path}_maintenance to the real url of the app.
    echo "rewrite ^${path}_maintenance/(.*)$ ${path}/\$1 redirect;" > "/etc/nginx/conf.d/$domain.d/maintenance.$app.conf"
    systemctl reload nginx

    # Sleep 4 seconds to let the browser reload the pages and redirect the user to the app.
    sleep 4

    # Then remove the temporary files used for the maintenance.
    rm "/var/www/html/maintenance.$app.html"
    rm "/etc/nginx/conf.d/$domain.d/maintenance.$app.conf"

    systemctl reload nginx
}
