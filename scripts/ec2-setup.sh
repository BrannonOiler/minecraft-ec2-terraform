## LOCAL FUNCTIONS
echo_success() { echo -e "\033[32m$1\033[0m"; }
echo_success_bold() { echo -e "\033[1;32m$1\033[0m"; }
echo_warning() { echo -e "\033[33m$1\033[0m"; }
echo_warning_bold() { echo -e "\033[1;33m$1\033[0m"; }
echo_info() { echo -e "\033[34m$1\033[0m"; }
echo_info_bold() { echo -e "\033[1;34m$1\033[0m"; }
echo_error() { echo -e "\033[31m$1\033[0m"; }
silently() { "$@" >/dev/null 2>&1; }

## PACKAGE INSTALLATION
echo_info "Updating package lists and upgrading existing packages..."
silently sudo dnf update -y

echo_info "Installing necessary packages: Java 17 (Amazon Corretto), netcat, pip, unzip..."
silently sudo dnf install -y firewall-cmd java-17-amazon-corretto nc python3-pip unzip

#! This must be installed as root so that mcstatus is available to systemd services/timers
#? Installs to /usr/local/bin/mcstatus
echo_info "Installing mcstatus using pip...."
silently sudo pip3 install mcstatus

echo_success "Package installation complete."

## SWAP FILE
if [ ! -f /swapfile ]; then
    echo_info "Creating 4GB swap file..."
    silently sudo fallocate -l 4G /swapfile
    silently sudo chmod 600 /swapfile
    silently sudo mkswap /swapfile
    silently sudo swapon /swapfile

    echo_info "Adding swap entry to /etc/fstab..."
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    echo_success "Swap file created and enabled."
else
    echo_warning "Swap file already exists, skipping swap setup."
fi

## MINECRAFT SERVER INSTALL AND SETUP
if [ ! -d /home/ec2-user/minecraft-server ]; then
    echo_info "Setting up Minecraft server directory..."
    mkdir -p /home/ec2-user/minecraft-server
    cd /home/ec2-user/minecraft-server

    echo_info "Downloading Homestead Minecraft server..."
    silently wget -O homestead-minecraft-server.zip "https://drive.usercontent.google.com/download?id=18gZsXewdy7sHZGuXkzvg6Y2ns5ybrBHl&export=download&authuser=0&confirm=t&uuid=64fe7a70-cf2a-45d5-97b1-c9373bf7d414&at=APcXIO0Om3jZNXP42D7GizFE8fka%3A1769732509376"

    echo_info "Unzipping server files..."
    silently unzip homestead-minecraft-server.zip -d .
    rm homestead-minecraft-server.zip
    rm -f wget-log

    echo_info "Moving server files to correct location..."
    silently sudo mv Homestead1.2.9.4/* .
    silently sudo rmdir Homestead1.2.9.4

    echo_info "Accepting Minecraft EULA..."
    echo "eula=true" >eula.txt

    echo_info "Changing settings in variables.txt..."
    sed -i 's/^JAVA_ARGS=.*/JAVA_ARGS="-Xmx12G -Xms8G"/' variables.txt

    echo_info "Changing settings in server.properties..."
    sed -i 's/^enforce-whitelist=.*/enforce-whitelist=true/' server.properties
    sed -i 's/^max-players=.*/max-players=4/' server.properties
    sed -i 's/^pvp=.*/pvp=false/' server.properties
    sed -i 's/^white-list=.*/white-list=true/' server.properties

    echo_success "Minecraft server setup complete."
else
    echo_warning "Minecraft server directory already exists, skipping server setup."
fi

## NAVIGATE TO HOME DIRECTORY
# Navigate back to home directory
cd /home/ec2-user

## SERVICE - MANAGE MC SERVER WITH SYSTEMD
if [ ! -f /etc/systemd/system/minecraft.service ]; then
    echo_info "Creating Minecraft server systemd service..."
    mc_service_config=$(
        cat <<EOF
[Unit]
Description=Minecraft Server
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/home/ec2-user/minecraft-server
ExecStart=/bin/bash start.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    )

    echo "$mc_service_config" | silently sudo tee /etc/systemd/system/minecraft.service

    echo_info "Enabling Minecraft server service to start on boot..."
    silently sudo systemctl enable minecraft.service
    silently sudo systemctl daemon-reload

    echo_success "Minecraft server systemd service created and enabled."
else
    echo_warning "Minecraft server systemd service already exists, skipping service setup."
fi

## AUTO SHUTDOWN SCRIPT
#? Creates or updates the auto-shutdown service and timer to check player count every 15 minutes and shut down if no players are online for two consecutive checks
echo_info "Making sure auto-shutdown.sh is executable..."
chmod +x /home/ec2-user/scripts/auto-shutdown.sh

# Set up or update systemd service and timer for auto-shutdown
echo_info "Creating and/or updating auto-shutdown systemd service and timer..."

auto_shutdown_service=$(
    cat <<EOF
[Unit]
Description=Auto Shutdown Minecraft EC2 Instance

[Service]
Type=simple
User=ec2-user
ExecStart=/home/ec2-user/scripts/auto-shutdown.sh
EOF
)
echo "$auto_shutdown_service" | silently sudo tee /etc/systemd/system/auto-shutdown.service

auto_shutdown_timer=$(
    cat <<EOF
[Unit]
Description=Run auto-shutdown every 5 minutes

[Timer]
OnBootSec=10min
OnUnitActiveSec=5min
Unit=auto-shutdown.service

[Install]
WantedBy=timers.target
EOF
)
echo "$auto_shutdown_timer" | silently sudo tee /etc/systemd/system/auto-shutdown.timer

echo_info "Reloading systemd and enabling auto-shutdown timer..."
silently sudo systemctl daemon-reload
silently sudo systemctl enable auto-shutdown.service
silently sudo systemctl enable auto-shutdown.timer
silently sudo systemctl restart auto-shutdown.timer

echo_success "Auto-shutdown service and timer created/updated and enabled."
echo

## FINAL STATUS MESSAGE
echo_success_bold "========================================================="
echo_success_bold "============ Minecraft EC2 Setup Complete! =============="
echo_success_bold "========================================================="
echo_info_bold "Server directory: /home/ec2-user/minecraft-server"
echo_info_bold "To check server status: sudo systemctl status minecraft"
echo_info_bold "To start server: sudo systemctl start minecraft"
echo_info_bold "To stop server: sudo systemctl stop minecraft"
echo_success_bold "========================================================="
echo_warning_bold "Auto-shutdown will power off the instance if no players"
echo_warning_bold "are online for two consecutive checks (every 5 minutes)."
echo_success_bold "========================================================="
echo
