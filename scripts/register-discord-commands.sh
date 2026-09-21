#!/bin/bash
set -euo pipefail

if [ $# -lt 3 ]; then
    echo "Usage: $0 <DISCORD_APPLICATION_ID> <DISCORD_TOKEN> <GUILD_ID>"
    echo "Global replacement is intentionally separate: $0 <DISCORD_APPLICATION_ID> <DISCORD_TOKEN> --replace-global"
    echo "Safe legacy cleanup: $0 <DISCORD_APPLICATION_ID> <DISCORD_TOKEN> --remove-legacy-global"
    exit 1
fi

application_id="$1"
token="$2"
target="$3"

if [ "$target" = "--remove-legacy-global" ]; then
    echo "Removing only legacy global /mc commands."
    DISCORD_APPLICATION_ID="$application_id" DISCORD_TOKEN="$token" node <<'NODE'
const applicationId = process.env.DISCORD_APPLICATION_ID;
const token = process.env.DISCORD_TOKEN;
const baseUrl = `https://discord.com/api/v10/applications/${applicationId}/commands`;
const legacyNames = new Set(["mc"]);

(async () => {
  const headers = { Authorization: `Bot ${token}` };
  const list = await fetch(baseUrl, { headers });
  if (!list.ok) {
    console.error(`Discord command lookup failed (HTTP ${list.status}).`);
    process.exit(1);
  }

  const commands = await list.json();
  const legacyCommands = commands.filter((command) => legacyNames.has(command.name));
  for (const command of legacyCommands) {
    const response = await fetch(`${baseUrl}/${command.id}`, { method: "DELETE", headers });
    if (!response.ok) {
      console.error(`Could not remove /${command.name} (HTTP ${response.status}).`);
      process.exit(1);
    }
    console.log(`Removed legacy global /${command.name}.`);
  }
  if (legacyCommands.length === 0) console.log("No legacy global commands found.");
})().catch((error) => {
  console.error("Discord legacy-command cleanup failed.", error);
  process.exit(1);
});
NODE
    exit $?
elif [ "$target" = "--replace-global" ]; then
    commands_url="https://discord.com/api/v10/applications/${application_id}/commands"
    echo "Replacing all global commands for this application."
else
    commands_url="https://discord.com/api/v10/applications/${application_id}/guilds/${target}/commands"
fi

command_payload='[
  {
    "name": "start",
    "description": "Start a Minecraft server",
    "options": [{ "type": 3, "name": "server", "description": "Choose a server", "required": true, "autocomplete": true }]
  },
  {
    "name": "stop",
    "description": "Gracefully stop a Minecraft server",
    "options": [{ "type": 3, "name": "server", "description": "Choose a server", "required": true, "autocomplete": true }]
  },
  {
    "name": "status",
    "description": "Show Minecraft fleet status"
  }
]'

response=$(curl --silent --show-error --write-out "\n%{http_code}" \
    --request PUT "$commands_url" \
    --header "Authorization: Bot ${token}" \
    --header "Content-Type: application/json" \
    --data "$command_payload")
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
    echo "Registered /start, /stop, and /status fleet commands successfully."
else
    echo "Discord command registration failed (HTTP $http_code)."
    echo "$body"
    exit 1
fi
