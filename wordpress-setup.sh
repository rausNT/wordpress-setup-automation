
#!/bin/bash

# Log file for debugging
log_file="/var/log/wordpress_setup.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$log_file"
}

log "Starting script execution..."

# Function to check if the script is being run on the correct OS and version
check_os() {
    log "Checking operating system..."
    if [[ "$(lsb_release -is)" != "Ubuntu" || "$(lsb_release -rs)" != "24.04" ]]; then
        log "Error: This script is designed for Ubuntu 24.04 only."
        exit 1
    fi
}

# Function to check if there is enough disk space (minimum 2 GB required)
check_disk_space() {
    log "Checking disk space..."
    local available_space=$(df / | tail -1 | awk '{print $4}')
    if (( available_space < 2000000 )); then
        log "Error: Not enough disk space. At least 2 GB is required."
        exit 1
    fi
}

# Function to check for internet connectivity
check_internet() {
    log "Checking internet connection..."
    if ! ping -c 1 google.com &> /dev/null; then
        log "Error: No internet connection. Please check your network."
        exit 1
    fi
}

# Function to check if the script is run as sudo
check_sudo() {
    log "Checking if script is run as root..."
    if [[ $(id -u) -ne 0 ]]; then
        log "Error: This script must be run as root or with sudo."
        exit 1
    fi
}

# Prompt for clean installation
clean_install_prompt() {
    log "Prompting for clean installation..."
    read -p "WARNING: This will erase all existing data on the server. Do you want to proceed with a clean installation? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log "Performing clean installation..."
        sudo rm -rf /var/www/*
        sudo rm -rf /etc/nginx/sites-enabled/*
        sudo rm -rf /etc/nginx/sites-available/*
        sudo mysql -e "DROP DATABASE IF EXISTS ${DB_NAME};"
        sudo mysql -e "DROP USER IF EXISTS '${DB_USER}'@'localhost';"
    else
        log "Clean installation aborted. Exiting."
        exit 1
    fi
}

# Run all pre-checks
check_os
check_disk_space
check_internet
check_sudo

# Function to safely read user input
read_input() {
    local prompt="$1"
    local default_value="$2"
    read -p "$prompt" input
    echo "${input:-$default_value}"
}

log "Collecting user input..."
SITE_DOMAIN=$(read_input "Enter the domain name for the website (e.g., perfectfont.site): " "example.com")
DB_NAME=$(read_input "Enter the database name for WordPress (default: wordpress_db): " "wordpress_db")
DB_USER=$(read_input "Enter the database username (default: wordpress_user): " "wordpress_user")
DB_PASSWORD=$(read_input "Enter the database password: " "")

if [[ -z "$DB_PASSWORD" ]]; then
    log "Error: Database password cannot be empty. Please try again."
    exit 1
fi

# Ask for clean installation
clean_install_prompt

# Install necessary packages
log "Installing necessary packages..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y nginx mysql-server php8.3-fpm php8.3-mysql php8.3-curl php8.3-gd php8.3-mbstring php8.3-xml php8.3-zip unzip wget ufw fail2ban clamav clamav-daemon certbot python3-certbot-nginx cockpit

# Configure MySQL
log "Configuring MySQL..."
sudo mysql -e "CREATE DATABASE ${DB_NAME};"
sudo mysql -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"
sudo mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Configure Nginx
log "Configuring Nginx..."
cat <<EOL | sudo tee /etc/nginx/sites-available/wordpress
server {
    listen 80;
    server_name ${SITE_DOMAIN};

    root /var/www/wordpress;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires max;
        log_not_found off;
    }
}
EOL

sudo ln -s /etc/nginx/sites-available/wordpress /etc/nginx/sites-enabled/
sudo unlink /etc/nginx/sites-enabled/default

# Test and reload Nginx configuration
log "Testing Nginx configuration..."
if sudo nginx -t; then
    sudo systemctl reload nginx
    log "Nginx has been successfully configured and reloaded."
else
    log "Error in Nginx configuration. Please check the settings."
    exit 1
fi

# Download and configure WordPress
log "Downloading and configuring WordPress..."
sudo mkdir -p /var/www/wordpress
sudo wget https://wordpress.org/latest.zip -O /tmp/wordpress.zip
sudo unzip /tmp/wordpress.zip -d /var/www/
sudo chown -R www-data:www-data /var/www/wordpress
sudo chmod -R 755 /var/www/wordpress

# Configure UFW
log "Configuring UFW firewall..."
sudo ufw allow 'Nginx Full'
sudo ufw allow 9090
sudo ufw enable

# Configure Fail2Ban for security
log "Configuring Fail2Ban..."
sudo cat <<EOL | sudo tee /etc/fail2ban/jail.local
[nginx-http-auth]
enabled = true

[nginx-badbot]
enabled = true
filter = nginx-badbot
logpath = /var/log/nginx/access.log
maxretry = 5
bantime = 3600
findtime = 300

[nginx-noscript]
enabled = true
filter = nginx-noscript
logpath = /var/log/nginx/access.log
maxretry = 5
bantime = 3600
findtime = 300
EOL

sudo systemctl restart fail2ban

# Configure ClamAV for antivirus
log "Configuring ClamAV..."
sudo systemctl stop clamav-freshclam
sudo freshclam
sudo systemctl start clamav-freshclam

# Install SSL certificate using Certbot
log "Installing SSL certificate..."
if sudo certbot --nginx -d ${SITE_DOMAIN} -n --agree-tos --email admin@${SITE_DOMAIN}; then
    log "SSL certificate successfully installed."
else
    log "Error installing SSL certificate. Please check Certbot logs."
    exit 1
fi

# Enable automatic SSL certificate renewal
log "Enabling Certbot timer for automatic SSL renewal..."
sudo systemctl enable certbot.timer

# Ensure PHP-FPM is active
log "Checking PHP-FPM status..."
if ! sudo systemctl is-active --quiet php8.3-fpm; then
    log "PHP-FPM is not running. Attempting to start..."
    sudo systemctl start php8.3-fpm
fi

if ! sudo systemctl is-enabled --quiet php8.3-fpm; then
    log "PHP-FPM is not enabled at startup. Enabling..."
    sudo systemctl enable php8.3-fpm
fi

# Ensure Cockpit is active
log "Checking Cockpit status..."
if ! sudo systemctl is-active --quiet cockpit; then
    log "Cockpit is not running. Attempting to start..."
    sudo systemctl start cockpit
fi

if ! sudo systemctl is-enabled --quiet cockpit; then
    log "Cockpit is not enabled at startup. Enabling..."
    sudo systemctl enable cockpit
fi

# Display final configuration
log "WordPress installation completed. Displaying configuration details..."

cat <<EOM
===========================================
WordPress has been successfully installed!

Site Details:
- Website URL: https://${SITE_DOMAIN}
- Admin setup: https://${SITE_DOMAIN}/wp-admin/setup-config.php

Database connection details:
- Database Name: ${DB_NAME}
- Database User: ${DB_USER}
- Database Password: [hidden for security]
  (You used this password during the setup.)

Cockpit (Server Management) Details:
- URL: https://${SITE_DOMAIN}:9090
- Username: ${DB_USER}
- Password: Same as your database password.

Recommendations:
1. If the website URL is not working:
   - Verify your domain's DNS A record is correctly pointed to the server's IP.
   - Ensure the firewall settings allow HTTP/HTTPS traffic.

2. Use the Cockpit interface for easy server management.

3. Remember to regularly monitor your server and update software for security.

Thank you for using this script! Enjoy your new WordPress website.
===========================================
EOM

