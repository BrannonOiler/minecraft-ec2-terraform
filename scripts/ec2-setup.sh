# Update package lists
sudo dnf update -y

# Install OpenJDK 17, and unzip for running the server in the background
sudo dnf install -y java-17-amazon-corretto unzip


# Resize existing swap file to 4G (if already created)
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
# Ensure /etc/fstab has the correct entry (add if missing):
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Create directory for minecraft server files, cd into it
mkdir -p /home/ec2-user/minecraft-server
cd /home/ec2-user/minecraft-server

# Download Homestead Minecraft server
#? It's a ZIP file, so we need to unzip it
wget -O homestead-minecraft-server.zip "https://drive.usercontent.google.com/download?id=18gZsXewdy7sHZGuXkzvg6Y2ns5ybrBHl&export=download&authuser=0&confirm=t&uuid=64fe7a70-cf2a-45d5-97b1-c9373bf7d414&at=APcXIO0Om3jZNXP42D7GizFE8fka%3A1769732509376"

# Unzip homestead-minecraft-server.zip into . (not a subfolder), then remove zip and wget-log
unzip homestead-minecraft-server.zip -d .
rm homestead-minecraft-server.zip
rm wget-log

# Move contents of "Homestead1.2.9.4" folder up one level, then remove empty folder
sudo mv Homestead1.2.9.4/* .
sudo rmdir Homestead1.2.9.4

# Accept the Minecraft EULA
echo "eula=true" > eula.txt

# Edit the amount of RAM by searching for the JAVA_ARGS line in variables.txt and changing -Xmx and -Xms values
#! This is dependent on the RAM available on the chosen EC2 instance type.
sed -i 's/^JAVA_ARGS=.*/JAVA_ARGS="-Xmx12G -Xms8G"/' variables.txt

# Create a service to manage the Minecraft server, save it to systemd folder
echo "[Unit]
Description=Minecraft Server
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/home/ec2-user/minecraft-server
ExecStart=/bin/bash start.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/minecraft.service

# Enable the service to start on boot
sudo systemctl enable minecraft.service
sudo systemctl daemon-reload