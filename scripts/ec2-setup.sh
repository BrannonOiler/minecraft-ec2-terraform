## LOCAL FUNCTIONS
echo_success() {
    #? ANSI escape code for green is \033[32m, reset is \033[0m
    echo -e "\033[32m$1\033[0m"
}

echo_warning() {
    #? ANSI escape code for yellow is \033[33m, reset is \033[0m
    echo -e "\033[33m$1\033[0m"
}

## PACKAGE INSTALLATION
echo_success "Updating package lists..."
sudo dnf update -y

echo_success "Installing necessary packages: crontab, Java 17 (Amazon Corretto), netcat, pip, unzip..."
sudo dnf install -y crontab java-17-amazon-corretto nc python3-pip unzip

echo_success "Installing mcstatus using pip..."
pip3 install mcstatus --user

## SWAP FILE
if [ ! -f /swapfile ]; then
    echo_success "Creating 4GB swap file..."
    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile

    echo_success "Adding swap entry to /etc/fstab..."
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
else
    echo_warning "Swap file already exists, skipping swap setup."
fi

## MINECRAFT SERVER INSTALL AND SETUP
if [ ! -d /home/ec2-user/minecraft-server ]; then
    echo_success "Setting up Minecraft server directory..."
    mkdir -p /home/ec2-user/minecraft-server
    cd /home/ec2-user/minecraft-server

    echo_success "Downloading Homestead Minecraft server..."
    wget -O homestead-minecraft-server.zip "https://drive.usercontent.google.com/download?id=18gZsXewdy7sHZGuXkzvg6Y2ns5ybrBHl&export=download&authuser=0&confirm=t&uuid=64fe7a70-cf2a-45d5-97b1-c9373bf7d414&at=APcXIO0Om3jZNXP42D7GizFE8fka%3A1769732509376"

    echo_success "Unzipping server files..."
    unzip homestead-minecraft-server.zip -d .
    rm homestead-minecraft-server.zip
    rm -f wget-log

    echo_success "Moving server files to correct location..."
    sudo mv Homestead1.2.9.4/* .
    sudo rmdir Homestead1.2.9.4

    echo_success "Accepting Minecraft EULA..."
    echo "eula=true" > eula.txt

    echo_success "Setting Java memory arguments in variables.txt..."
    sed -i 's/^JAVA_ARGS=.*/JAVA_ARGS="-Xmx12G -Xms8G"/' variables.txt
else
    echo_warning "Minecraft server directory already exists, skipping server setup."
fi

# Navigate back to home directory
cd /home/ec2-user

## AUTO SHUTDOWN SCRIPT
echo_success "Making auto-shutdown.sh executable..."
chmod +x /home/ec2-user/scripts/auto-shutdown.sh

# Set up a cron job to run the auto-shutdown.sh script every 15 minutes
if [ ! -f /etc/cron.d/auto-shutdown ]; then
    echo_success "Setting up cron job for auto-shutdown..."
    echo "*/15 * * * * ec2-user /home/ec2-user/scripts/auto-shutdown.sh" | sudo tee /etc/cron.d/auto-shutdown
    sudo chmod 644 /etc/cron.d/auto-shutdown
    sudo systemctl restart crond
else
    echo_warning "Cron job for auto-shutdown already exists, skipping setup."
fi

## SERVICE - MANAGE MC SERVER WITH SYSTEMD
if [ ! -f /etc/systemd/system/minecraft.service ]; then
    echo_success "Creating Minecraft server systemd service..."
    mc_service_config=$(cat <<EOF
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
    
    echo "$mc_service_config" | sudo tee /etc/systemd/system/minecraft.service

    echo_success "Enabling Minecraft server service to start on boot..."
    sudo systemctl enable minecraft.service
    sudo systemctl daemon-reload
else
    echo_warning "Minecraft server systemd service already exists, skipping service setup."
fi
