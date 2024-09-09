#!/bin/bash

### ======== Settings ======== ###

# Which 1C Enterprise 8 components should be installed
onec_install_components=server,ws,liberica_jre,server_admin

# PostgreSQL version
pg_ver=16

# Dependencies to install
install_apt_packages="curl wget jq tar unzip fontconfig"

# Oneget
oneget_get=platform:linux.x64@latest
oneget_get_filter="--filter platform=server64_8"
oneget_repo=oneget
oneget_repo_owner=Pringlas
oneget_install_file=oneget_Linux_x86_64.tar.gz
oneget_dir="/opt/oneget"
oneget_downloads_platform="${oneget_dir}/downloads/platform83"

# 1C RAS
onec_ras_server=localhost
onec_ras_port=1545

# DBMS
onec_dbms=PostgreSQL
onec_dbms_server=localhost
onec_dbms_user=postgres

# Gilev TPC-1C
onec_db_new_name=gilev
onec_db_new_dt_url="http://www.gilev.ru/1c/tpc/GILV_TPC_G1C_83.dt"
onec_db_new_dt=$(basename "$onec_db_new_dt_url")

# Path to localegen configuration file
localegen_conf=/etc/locale.gen

# Which locale to use
locale=ru_RU.UTF-8

# Path to postgresql.conf
pg_conf=/var/lib/pgpro/1c-$pg_ver/data/postgresql.conf

# Link to the script that configures the Postgres Pro repositories
pg_repo_sh_link=https://repo.postgrespro.ru/1c/1c-$pg_ver/keys/pgpro-repo-add.sh

# Name of the script that configures the Postgres Pro repositories
pg_repo_sh=$(basename $pg_repo_sh_link)

# The directory where the installed releases of the 1C Enterprise 8 platform are located
onec_dir_platform=/opt/1cv8/x86_64

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

# Function that receives input from the user
function read_user_input {
    declare -n result=$2
    text=$1
    read -p "$text" result
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

# Function that creates a new base in a 1C cluster from a .dt file
function onec_create_db_dt {
    # Determining the most recent version of the platform among the installed ones
    onec_release_latest_installed=$(ls $onec_dir_platform | sort -nk 2 | tail -1)

    # Path to rac utility
    onec_rac_path="${onec_dir_platform}/${onec_release_latest_installed}/rac"

    # Path to the idcmd utility
    onec_ibcmd_path="${onec_dir_platform}/${onec_release_latest_installed}/ibcmd"

    # Defining the 1С cluster guid
    cluster_guid=$($onec_rac_path $onec_ras_server:$onec_ras_port cluster list | grep cluster | awk '{print $3}')

    # Downloading .dt upload file
    curl -fsSL $onec_db_new_dt_url -O

    # Creating a 1С base from a .dt file in a DBMS directly
    $onec_ibcmd_path infobase create --dbms=$onec_dbms \
    --db-server=$onec_dbms_server --db-user=$onec_dbms_user --db-pwd=$onec_dbms_pass \
    --db-name=$onec_db_new_name --create-database --restore=$onec_db_new_dt

    # Adding the created base to 1C cluster
    $onec_rac_path $onec_ras_server:$onec_ras_port infobase \
    --cluster=$cluster_guid create \
    --name="$onec_db_new_name" \
    --dbms="$onec_dbms" \
    --db-server="$onec_dbms_server" \
    --db-name="$onec_db_new_name" \
    --locale=ru \
    --db-user="$onec_dbms_user" \
    --db-pwd="$onec_dbms_pass" \
    --license-distribution=allow

    # Getting the list of bases in the 1С cluster
    onec_cluster_db_list=$($onec_rac_path $onec_ras_server:$onec_ras_port infobase summary list --cluster=$cluster_guid | awk '{print $3}')

    # Set the 1C base name in the variable
    search_value="${onec_db_new_name}"

    # Determining the guid of a 1C base by its name
    prev=
    while read -r line; do
        if [ ! -z "${prev}" ];then
            line_one="${prev}"
            line_two="${line}"
            if [[ "$line_two" == "$search_value" ]]; then
                previous_line=$(echo "$line_one")  
                onec_db_new_guid=$(echo "$previous_line")
                break
            fi
        fi
    prev="${line}"
    done <<< "$onec_cluster_db_list"
}

# Function that displays the start message and waits for user confirmation to continue
function message_before_start {
    # Print message to console
    clear
    echo
    echo "IP: $show_ip"
    echo
    echo "Скрипт: $script_name"
    echo
    echo "Лог: $logfile_path"
    echo
    echo "Будут установлены:"
    echo
    echo "${echo_tab}1C: $onec_install_components"
    echo
    echo "${echo_tab}СУБД: Postgres Pro $pg_ver"
    echo

    # Wait until the user presses enter
    read -p "Нажмите Enter, чтобы начать: "
}

# Function displaying the final summary of the script execution results
function message_at_the_end {
    # Print message to console
    clear
    echo
    echo "IP: $show_ip"
    echo
    echo "Скрипт: $script_name"
    echo
    echo "Лог: $logfile_path"
    echo
    echo "Установлены:"
    echo
    echo "${echo_tab}1C - $onec_installed_version"
    echo "${echo_tab}oneget - $oneget_ver"
    echo "${echo_tab}PostgreSQL - $pg_installed_version"
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
    echo "Созданы базы 1С (guid | имя):"
    echo
    echo "${echo_tab}$onec_db_new_guid | $onec_db_new_name"
    echo
}

### -------- Functions -------- ###

### -------- Preparation -------- ###

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

# Path to this script
script_path="${script_dir}/${script_name}"

# Path to log file
logfile_path="${script_dir}/${script_name%%.*}.log"

# For console output
echo_tab='     '
show_ip=$(hostname -I)

# Privilege escalation
elevate

# Start logging
exec > >(tee -a "$logfile_path") 2>&1

### -------- Preparation -------- ###

### -------- Script start  -------- ###

# Message to log
log "Script start"

# Print message to console
message_before_start

### -------- Script start -------- ###

### -------- Receiving data from user -------- ###

# Message to log
log "Receiving data from user"

# Output to console
clear
echo

# Getting ITS account login
read_user_input "ИТС -> логин: " "onec_its_user"

# Getting ITS account password
read_pass "ИТС -> пароль: " "onec_its_pass"

# Get password for postgres user
read_pass "СУБД -> пароль для пользователя 'postgres': " "onec_dbms_pass"

### -------- Receiving data from user -------- ###

### -------- Dependency installation -------- ###

# Message to log
log "Installing dependencies"

# Install packages necessary for further work
apt update && apt install -y $install_apt_packages

# Installing fonts from Microsoft (non-interactive, without questions)
sh -c "echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections"
apt install -y msttcorefonts -qq
fc-cache –fv

### -------- Dependency installation -------- ###

### -------- Setting up locale -------- ###

# Message to log
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
oneget_download_link=https://github.com/$oneget_repo_owner/$oneget_repo/releases/download/$oneget_ver/$oneget_install_file

# Continue only if the file does not exist at the specified path
if [ ! -f "$oneget_path" ]; then
    mkdir -p $oneget_dir/$oneget_ver
    curl -fsSL $oneget_download_link -o $oneget_dir/$oneget_ver/$oneget_install_file
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

# Message to log
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

# Checking the installed version
if [ -d "$onec_dir_platform/$onec_release" ]; then
    onec_installed_version="${onec_release}"
fi

### -------- Download and install 1C -------- ###

### -------- Installing Postgres Pro -------- ###

# Message to log
log "Installing Postgres Pro"

# Download the script that adds the repository
curl -fsSL $pg_repo_sh_link -O

# Run the script
sh $pg_repo_sh

# Start Postgres Pro installation
apt update && apt install -y postgrespro-1c-$pg_ver

# Set password for postgres user
su - postgres -c "psql -c \"ALTER USER postgres WITH PASSWORD '$onec_dbms_pass';\""

# Allow connection to the database
find_and_replace $pg_conf "#listen_addresses = 'localhost'" "listen_addresses = 'localhost'"

# Restarting the service
systemctl restart postgrespro-1c-$pg_ver

# Remove the script that adds the repository
rm $pg_repo_sh

# Checking the installed version
pg_installed_version=$(postgres --version | awk '{print $3}')

### -------- Postgres Pro -------- ###

### -------- Gilev TPC-1C -------- ###

# Message to log
log "Creating 'Gilev TPC-1C' base"

# Starting the function of base creation
onec_create_db_dt

### -------- Gilev TPC-1C -------- ###

### -------- Script end -------- ###

# Message to log
log "Script end"

# Print message to console
message_at_the_end

### -------- Script end -------- ###