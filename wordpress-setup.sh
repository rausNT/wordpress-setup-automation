#!/bin/bash

# Function to check if the script is being run on the correct OS and version
check_os() {
    if [[ "$(lsb_release -is)" != "Ubuntu" || "$(lsb_release -rs)" != "24.04" ]]; then
        echo "Error: This script is designed for Ubuntu 24.04 only."
        exit 1
    fi
}

# Function to check if there is enough disk space (minimum 2 GB required)
check_disk_space() {
    local available_space=$(df / | tail -1 | awk '{print $4}')
    if (( available_space < 2000000 )); then
        echo "Error: Not enough disk space. At least 2 GB is required."
        exit 1
    fi
}

# Function to check for internet connectivity
check_internet() {
    if ! ping -c 1 google.com &> /dev/null; then
        echo "Error: No internet connection. Please check your network."
        exit 1
    fi
}

# Function to check if the script is run as sudo
check_sudo() {
    if [[ $(id -u) -ne 0 ]]; then
        echo "Error: This script must be run as root or with sudo."
        exit 1
    fi
}

# Function to warn and clear server for clean installation
clean_install_prompt() {
    read -p "This will erase all existing data on the server. Proceed with a clean installation? (Y/N): " confirm
    case "$confirm" in
        [Yy]*)
            echo "Performing clean installation..."
            rm -rf /var/www/* /etc/nginx/sites-available/* /etc/nginx/sites-enabled/*
            rm -rf /etc/mysql/*
            echo "Server cleared for clean installation."
            ;;
        [Nn]*)
            echo "Clean installation aborted. Exiting..."
            exit 1
            ;;
        *)
            echo "Invalid input. Please enter Y or N
