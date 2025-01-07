# WordPress Setup Automation

A comprehensive automation script for setting up WordPress on Ubuntu 24.04 with secure configurations, SSL, and performance optimizations.

## Features
Automated WordPress Installation: Sets up WordPress with Nginx, MySQL, PHP, and SSL.
Enhanced Security: Includes Fail2Ban for DDoS protection and ClamAV for antivirus scanning.
Automatic SSL Configuration: Installs and renews SSL certificates using Certbot.
System Pre-checks: Verifies OS version, disk space, internet connection, and more before installation.
Requirements
Ubuntu 24.04 (script will validate the OS version).
At least 2 GB of free disk space.
Root or sudo privileges.
## Quick Start
Run the script directly using the following command:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/rausNT/wordpress-setup-automation/main/wordpress-setup.sh)
```

## What the Script Does

Checks your system for compatibility.
Installs and configures Nginx, MySQL, PHP, and WordPress.
Configures UFW, Fail2Ban, and ClamAV for added security.
Sets up SSL certificates with automatic renewal.
Provides detailed logs and prompts for easy debugging.
## Troubleshooting
Error: "Not enough disk space": Free up disk space and ensure at least 2 GB is available.
Error: "OS not supported": Ensure you are running Ubuntu 24.04.
Cannot access via HTTPS: Check the Certbot logs for SSL setup issues.
## License
For this project, I suggest using the MIT License, which is simple and permissive, allowing others to use and modify your script while protecting you from liability.
