# Steps

1. Connect to EC2 instance via this command:

   ```sh
   ssh -i ~/.ssh/personal-keys/minecraft-server-01-key-pair ec2-user@<IP_ADDRESS>
   ```

2. Run the commands in server-setup.sh script

3. Setup Minecraft client to work with Homestead server:
   - Open Prism Launcher
   - Select "Add Instance"
     - Find "Homestead - A Cozy Survival Experience" under the curseforge mods
     - Make sure to download the manual mods that cannot be downloaded automatically
   - Start the instance, join the server using the public IP: <SERVER_IP>:25565

4. Interact with the server as needed:
   - Reconnect via SSH:
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
