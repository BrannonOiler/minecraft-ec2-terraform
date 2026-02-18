#!/bin/bash

#? Check if arguments are provided
if [ $# -lt 2 ]; then
    echo "Usage: $0 <DISCORD_APPLICATION_ID> <DISCORD_TOKEN>"
    exit 1
fi

## ARGS AND CONFIG
DISCORD_APPLICATION_ID="$1"
DISCORD_TOKEN="$2"
DISCORD_COMMANDS_URL="https://discord.com/api/v9/applications/${DISCORD_APPLICATION_ID}/commands"
COMMANDS=(
    '{"name":"start","description":"Start the Minecraft server"}'
    '{"name":"stop","description":"Stop the Minecraft server"}'
    '{"name":"status","description":"Get the status of the Minecraft server"}'
)

#? Remove existing commands
existing_commands=$(curl -s -H "Authorization: Bot ${DISCORD_TOKEN}" "$DISCORD_COMMANDS_URL")
if [ -n "$existing_commands" ]; then
    command_ids=$(echo "$existing_commands" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    for id in $command_ids; do
        delete_response=$(curl -s -w "\n%{http_code}" -X DELETE "$DISCORD_COMMANDS_URL/$id" \
            -H "Authorization: Bot ${DISCORD_TOKEN}")
        delete_http_code=$(echo "$delete_response" | tail -n1)
        if [ "$delete_http_code" -eq 204 ]; then
            echo "✓ Deleted existing command with ID: $id"
        else
            echo "✗ Failed to delete command with ID: $id (HTTP $delete_http_code)"
        fi
    done
else
    echo "No existing commands to delete."
fi

#? Register each {command}
for command in "${COMMANDS[@]}"; do
    response=$(curl -s -w "\n%{http_code}" -X POST "$DISCORD_COMMANDS_URL" \
        -H "Authorization: Bot ${DISCORD_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$command")

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    command_name=$(echo "$command" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)

    if [ "$http_code" -eq 201 ] || [ "$http_code" -eq 200 ]; then
        echo "✓ Command '$command_name' created: $http_code"
    else
        echo "✗ Command '$command_name' failed: $http_code"
        echo "  Response: $body"
    fi
done
