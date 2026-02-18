# Instructions

Use these instructions to:

- Set up and connect to the Minecraft server (via Prism Launcher).
- Connect to the EC2 instance via SSH for server management.
- Set up the Discord bot via the developer portal and register the slash commands.

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

## Discord Bot Setup

<!-- 1. Create a bot at https://discord.com/developers/applications/
    1. Under “OAuth2”, select the “bot” scope then give the following permissions:
        1. Send Messages
        2. Manage Messages
        3. Read Message History
    2. Change integration type to “Guild Install” and copy the generated URL
        1. https://discord.com/oauth2/authorize?client_id=1471543096297783520&permissions=75776&integration_type=0&scope=bot
    3. Enable “Message Content Intent” under “Bot” settings
    4. Give it the following permissions (Permissions integer 75776): -->

1. Navigate to https://discord.com/developers/applications/ to create a bot
2. Under the `General Information` tab:
   1. Give it a name (`MCServerBot`) and a description - `Start, stop and view the status of our Homestead Minecraft server.`
   2. Copy the public key and add it to variables.tf under `discord_public_key`
   3. Once the terraform apply is complete, copy the function URL from the output and paste it into `Interactions Endpoint URL` in the Discord developer portal under "General Information"
3. Under the `Bot` tab:
   1. Set the icon and banner using the images in the `assets` folder
   2. Enable `Message Content Intent`
4. Run the `register-discord-commands.sh` script to register the slash commands with Discord:

   ```sh
   ./scripts/register-discord-commands.sh <DISCORD_APPLICATION_ID> <DISCORD_TOKEN>
   ```

   - `DISCORD_APPLICATION_ID` is under the `General Information` tab
   - `DISCORD_TOKEN` is under the `Bot` tab under `Token`. Keep this token secret!

5. Under the `Installation` tab:
   1. Make sure `User Install` and `Guild Install` are both enabled

6. Under the OAuth2 tab:
   1. Select `bot` under `Scopes` and the following permissions:
      1. Send Messages
      2. Manage Messages
      3. Read Message History
   2. Copy the generated URL and to add the bot to your server
