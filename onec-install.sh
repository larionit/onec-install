#!/bin/bash

### ======== Settings ======== ###

# Which 1C Enterprise 8 components should be installed
onec_install_components=server,ws,liberica_jre,server_admin

# PostgreSQL version
pg_ver=16

# Dependencies to install
install_apt_packages="curl wget jq tar unzip fontconfig"

# Path to localegen configuration file
localegen_conf=/etc/locale.gen

# Which locale to use
locale=ru_RU.UTF-8

# Oneget 
oneget_repo=oneget
oneget_repo_owner=Pringlas
oneget_install_file=oneget_Linux_x86_64.tar.gz
oneget_get=platform:linux.x64@latest
oneget_get_filter="--filter platform=server64_8"
oneget_dir="/opt/oneget"
oneget_downloads_platform="${oneget_dir}/downloads/platform83"

# Path to postgresql.conf
pg_conf=/var/lib/pgpro/1c-$pg_ver/data/postgresql.conf

# Name of the script that configures the Postgres Pro repositories
pg_repo_sh=pgpro-repo-add.sh

# Link to the script that configures the Postgres Pro repositories
pg_repo_sh_link=https://repo.postgrespro.ru/1c/1c-$pg_ver/keys/$pg_repo_sh

# Define the directory where this script is located
script_dir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# Define the name of this script
script_name=$(basename "$0")

# Defining the directory name and script name if the script is launched via a symbolic link located in /usr/local/bin
if [[ "$script_dir" == *"/usr/local/bin"* ]]; then
    real_script_path=$(readlink ${0})
    script_dir="$( cd -- "$(dirname "$real_script_path")" >/dev/null 2>&1 ; pwd -P )"
    script_name=$(basename "$real_script_path")
fi

# Path to log file
logfile_path="${script_dir}/${script_name%%.*}.log"

# For console output
echo_tab='     '
show_ip=$(hostname -I)

### ======== Settings ======== ###

### -------- Functions -------- ###

# Privilege escalation function
function elevate {
    if [ "$EUID" -ne 0 ]; then
        echo "This script must be run with superuser privileges. Trying to elevate privileges with sudo."
        exec sudo bash "$0" "$@"
        exit 1
    fi
}

# Function for logging (when called, it outputs a message to the console containing date, time and the text passed in the first argument)
function log {
    echo
    echo "$(date '+%Y-%m-%d %H:%M:%S') -> $1"
    echo
}

# Find and replace function
function find_and_replace {
    target=$1
    find=$2
    replace=$3
    time=$(date +%G_%m_%d-%H_%M_%S)
    cp $target $target.bk_$time
    sed -i "s/${find}/${replace}/g" $target
}

# Function that receives the password from the user
function read_pass {
    declare -n result=$2
    text=$1
    unset result
    prompt="$text"
    while IFS= read -p "$prompt" -r -s -n 1 char
    do
    if [[ $char == $'\0' ]]
    then
        break
    fi
    prompt='*'
    result+="$char"
    done
    echo
}

### -------- Functions -------- ###

### -------- Preparation -------- ###

# Privilege escalation
elevate

# Start logging
exec > >(tee -a "$logfile_path") 2>&1

### -------- Preparation -------- ###

### -------- Message before start  -------- ###

# Print message to console
clear
echo
echo "Script running: $script_name"
echo
echo "Log is written to: $logfile_path"
echo
echo "Components to be installed:"
echo
echo "${echo_tab}1C: $onec_install_components"
echo
echo "${echo_tab}DBMS: Postgres Pro $pg_ver"
echo

# Wait until the user presses enter
read -p "Press Enter to start: "

### -------- Message before start -------- ###

### -------- Receiving data from user -------- ###

log "Receiving data from user"

# Output to console
clear
echo

# Getting ITS account login
read -p "ITS -> login: " onec_its_user

# Getting ITS account password
read_pass "ITS -> password: " "onec_its_pass"

# Get password for postgres user
read_pass "DBMS -> Password for postgres user: " "pg_pass"

### -------- Receiving data from user -------- ###

### -------- Dependency installation -------- ###

log "Installing dependencies"

# Install packages necessary for further work
apt update && apt install -y $install_apt_packages

# Installing fonts from Microsoft (non-interactive, without questions)
sh -c "echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections"
apt install -y msttcorefonts -qq
fc-cache –fv

### -------- Dependency installation -------- ###

### -------- Setting up locale -------- ###

log "Setting up locale"

# Uncommenting the line we need
find_and_replace $localegen_conf "# $locale UTF-8" "$locale UTF-8"

# Generating locale
locale-gen $locale

# Setting the locale
update-locale LANG=$locale

# Applying changes without re-login
. /etc/default/locale

### -------- Setting up locale -------- ###

### -------- Installing oneget -------- ###

log  "Installing oneget"

# Determine the latest oneget release
oneget_latest_release=$(curl -s https://api.github.com/repos/$oneget_repo_owner/$oneget_repo/releases | \
    jq -r 'first(.[].tag_name | select(test("^v[0-9]")))')

# Specify the version to be installed
oneget_ver="${oneget_latest_release}"

# Set path to binary file
oneget_path="${oneget_dir}/${oneget_ver}/oneget"

# Set the link to download the oneget executable file
onetget_download_link=https://github.com/$oneget_repo_owner/$oneget_repo/releases/download/$oneget_ver/$oneget_install_file

# Continue only if the file does not exist at the specified path
if [ ! -f "$oneget_path" ]; then
    mkdir -p $oneget_dir/$oneget_ver
    curl -fsSL $onetget_download_link -o $oneget_dir/$oneget_ver/$oneget_install_file
    tar -xvzf $oneget_dir/$oneget_ver/$oneget_install_file -C $oneget_dir/$oneget_ver
    rm $oneget_dir/$oneget_ver/$oneget_install_file
fi

# Set the path for the symbolic link
oneget_symlink="/usr/local/bin/oneget"

# Create a symbolic link
if [ ! -L "$oneget_symlink" ]; then
    ln -s "$oneget_path" "$oneget_symlink"
fi

### -------- Installing oneget -------- ###

### -------- Download and install 1C -------- ###

log "Download and install 1C"

# Go to the oneget directory
cd $oneget_dir

# Download the installation files specified in the settings from releases.1c.ru
$oneget_path -u $onec_its_user -p $onec_its_pass get $oneget_get_filter $oneget_get

# Go to the script directory
cd $script_dir

# Search among the uploaded files for the most recent release
onec_release=$(ls $oneget_downloads_platform | sort -nk 2 | tail -1)

# Specify the name of the archive to be unpacked
onec_inst_zip="server64_${onec_release//./_}.zip"

# Unpack the archive
unzip "$oneget_downloads_platform/$onec_release/$onec_inst_zip" -d $oneget_downloads_platform/$onec_release

# Set the name of the installer
onec_run="setup-full-${onec_release}-x86_64.run"

# Start the installation of the specified components 
$oneget_downloads_platform/$onec_release/$onec_run --mode unattended --enable-components $onec_install_components

# Create a symbolic link for the 1C server service
systemctl link /opt/1cv8/x86_64/$onec_release/srv1cv8-$onec_release@.service

# Enable 1C server autorun
systemctl enable srv1cv8-$onec_release@

# Start the 1C server service
systemctl start srv1cv8-$onec_release@default

# Create a symbolic link for the administration server service
systemctl link /opt/1cv8/x86_64/$onec_release/ras-$onec_release.service

# Enable autorun of the administration server
systemctl enable ras-$onec_release

# Start the administration server
systemctl start ras-$onec_release

### -------- Download and install 1C -------- ###

### -------- Installing Postgres Pro -------- ###

log "Installing Postgres Pro"

# Download the script that adds the repository
curl -fsSL $pg_repo_sh_link -O

# Run the script
sh $pg_repo_sh

# Start Postgres Pro installation
apt update && apt install -y postgrespro-1c-$pg_ver

# Set password for postgres user
su - postgres -c "psql -c \"ALTER USER postgres WITH PASSWORD '$pg_pass';\""

# Allow connection to the database
find_and_replace $pg_conf "#listen_addresses = 'localhost'" "listen_addresses = 'localhost'"

# Restarting the service
systemctl restart postgrespro-1c-$pg_ver

# Remove the script that adds the repository
rm $pg_repo_sh

# Check the installed version
pg_installed_version=$(postgres --version | awk '{print $3}')

### -------- Postgres Pro -------- ###

### -------- Message at the end -------- ###

# Print message to console
clear
echo
echo Versions:
echo
echo "${echo_tab}1C: $onec_release"
echo "${echo_tab}oneget: $oneget_ver"
echo "${echo_tab}PostgreSQL: $pg_installed_version"
echo
echo 1C:
echo
systemctl --no-pager status srv1cv8-$onec_release@default | grep Active
echo
echo 1C RAS:
echo
systemctl --no-pager status ras-$onec_release | grep Active
echo
echo Postgres Pro:
echo
systemctl --no-pager status postgrespro-1c-$pg_ver | grep Active
echo
echo IP:
echo
echo "${echo_tab}$show_ip"
echo
echo "Log: $logfile_path"
echo

### -------- Message at the end -------- ###