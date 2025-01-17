#!/bin/bash

# Log file
log_file="/var/log/add_wordpress_site.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$log_file"
}

log "Starting script to add a new WordPress site..."

# Function to safely read user input
read_input() {
    local prompt="$1"
    local default_value="$2"
    read -p "$prompt" input
    echo "${input:-$default_value}"
}

# Function to detect non-ASCII domain names and convert to Punycode
is_cyrillic_domain() {
    local domain="$1"
    if [[ "$domain" =~ [^a-zA-Z0-9.-] ]]; then
        return 0  # True: domain contains non-ASCII characters
    else
        return 1  # False: domain is ASCII
    fi
}

# Ensure WP-CLI is installed
log "Checking for WP-CLI..."
if ! command -v wp &> /dev/null; then
    log "WP-CLI not found. Installing WP-CLI..."
    curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x wp-cli.phar
    sudo mv wp-cli.phar /usr/local/bin/wp
    log "WP-CLI installed successfully."
else
    log "WP-CLI is already installed."
fi

# Collecting user input
SITE_DOMAIN=$(read_input "Enter the domain name for the new website (e.g., example.com): " "example.com")

# Check if domain is Cyrillic and convert to Punycode if necessary
if is_cyrillic_domain "$SITE_DOMAIN"; then
    if ! command -v idn2 &> /dev/null; then
        log "idn2 utility is not installed. Installing..."
        sudo apt install -y idn2
    fi
    SITE_DOMAIN_PUNYCODE=$(idn2 "$SITE_DOMAIN")
    log "Detected non-ASCII domain. Converted to Punycode: $SITE_DOMAIN_PUNYCODE"
else
    SITE_DOMAIN_PUNYCODE="$SITE_DOMAIN"
    log "Detected ASCII domain. Using as-is: $SITE_DOMAIN"
fi

DB_NAME=$(read_input "Enter the database name for the new WordPress site (default: wordpress_new): " "wordpress_new")
DB_USER=$(read_input "Enter the database username for the new site (default: wp_user_new): " "wp_user_new")
DB_PASSWORD=$(read_input "Enter the database password for the new site: " "")
WP_ADMIN_EMAIL=$(read_input "Enter the administrator email for the new site: " "admin@example.com")

if [[ -z "$DB_PASSWORD" ]]; then
    log "Error: Database password cannot be empty. Exiting."
    exit 1
fi

# Create database and user
log "Creating new MySQL database and user..."
sudo mysql -e "CREATE DATABASE ${DB_NAME};"
sudo mysql -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"
sudo mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Create a directory for the new site
SITE_DIR="/var/www/${SITE_DOMAIN}"
sudo mkdir -p "$SITE_DIR"
sudo chown -R www-data:www-data "$SITE_DIR"
sudo chmod -R 755 "$SITE_DIR"

# Configure Nginx for the new site
log "Configuring Nginx for the new site..."
cat <<EOL | sudo tee /etc/nginx/sites-available/${SITE_DOMAIN_PUNYCODE}
server {
    listen 80;
    server_name ${SITE_DOMAIN_PUNYCODE};

    root ${SITE_DIR};
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

sudo ln -s /etc/nginx/sites-available/${SITE_DOMAIN_PUNYCODE} /etc/nginx/sites-enabled/

log "Testing Nginx configuration..."
if sudo nginx -t; then
    sudo systemctl reload nginx
    log "Nginx configuration for ${SITE_DOMAIN} successfully applied."
else
    log "Error in Nginx configuration. Exiting."
    exit 1
fi

# Download and configure WordPress
log "Downloading WordPress for the new site..."
sudo wget https://wordpress.org/latest.zip -O /tmp/wordpress.zip
sudo unzip /tmp/wordpress.zip -d "$SITE_DIR"
sudo mv "$SITE_DIR/wordpress/"* "$SITE_DIR"
sudo rm -rf "$SITE_DIR/wordpress"
sudo chown -R www-data:www-data "$SITE_DIR"

log "Creating wp-config.php for the new site..."
cat <<EOL | sudo tee ${SITE_DIR}/wp-config.php
<?php
define( 'DB_NAME', '${DB_NAME}' );
define( 'DB_USER', '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASSWORD}' );
define( 'DB_HOST', 'localhost' );
define( 'DB_CHARSET', 'utf8' );
define( 'DB_COLLATE', '' );
\$table_prefix = 'wp_';
define( 'WP_DEBUG', false );
if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
EOL

# Install WordPress
log "Installing WordPress for ${SITE_DOMAIN}..."
if sudo -u www-data wp core install --url="http://${SITE_DOMAIN}" \
    --title="New WordPress Site" \
    --admin_user="${DB_USER}" \
    --admin_password="${DB_PASSWORD}" \
    --admin_email="${WP_ADMIN_EMAIL}" \
    --path="$SITE_DIR"; then
    log "WordPress installed successfully for ${SITE_DOMAIN}."
else
    log "Error installing WordPress for ${SITE_DOMAIN}. Check logs."
    exit 1
fi

# Install SSL certificate
log "Installing SSL certificate for ${SITE_DOMAIN}..."
if sudo certbot --nginx -d ${SITE_DOMAIN_PUNYCODE} -n --agree-tos --email ${WP_ADMIN_EMAIL}; then
    log "SSL certificate installed successfully for ${SITE_DOMAIN}."
else
    log "Error installing SSL certificate for ${SITE_DOMAIN}. Check Certbot logs."
    exit 1
fi

cat <<EOM
===========================================
New WordPress site added successfully!

Site URL: http://${SITE_DOMAIN}
Admin Panel: http://${SITE_DOMAIN}/wp-admin

Database:
  Name: ${DB_NAME}
  User: ${DB_USER}
  Password: ${DB_PASSWORD}

SSL certificate applied successfully.
===========================================
EOM

