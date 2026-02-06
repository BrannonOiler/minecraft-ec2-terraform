# Instructions

Use these instructions to connect to the Minecraft server (via Prism Launcher) and connect to the EC2 instance via SSH for server management.

## Setup Minecraft Client

1. Open Prism Launcher
2. Select "Add Instance"
   1. Find "Homestead - A Cozy Survival Experience" under the curseforge mods
   2. Make sure to download the manual mods that cannot be downloaded automatically
3. Join the server using the public IP: <SERVER_IP>:25565

## SSH Access and Server Management

- Connect via SSH:
  ```sh
  ssh -i ~/.ssh/personal-keys/minecraft-server-01-key-pair ec2-user@<SERVER_IP>
  ```
- Restart/start/stop the server:
  ```sh
  sudo systemctl restart minecraft.service
  sudo systemctl start minecraft.service
  sudo systemctl stop minecraft.service
  ```
- Check the status, view logs of the server:
  ```sh
  sudo systemctl status minecraft.service
  sudo journalctl -u minecraft.service -f
  ```
