#!/bin/bash
#? Checks number of players on the Minecraft server and shuts down if two consecutive checks are zero

# CONSTANTS
MC_HOST="localhost"
MC_PORT=25565

# Player count file (to store previous count)
player_count_file="/tmp/mc-player-count.txt"

# Get the previous player count
#? Set to -1 if the file doesn't exist to avoid shutdown on first run
prev_count=$(head -n 1 "$player_count_file" 2>/dev/null || echo "-1")

# Use mcstatus to get current player count
mcstatus_output=$(mcstatus "$MC_HOST" status 2>&1)

#? Handle potential errors from mcstatus
if [[ "$mcstatus_output" == *"Error"* ]]; then
    echo "Error checking Minecraft server status: $mcstatus_output"
    player_count=0
else
    player_count=$(echo "$mcstatus_output" | grep -oP 'players: \K\d+')
fi

# Update {player_count_file} with the current count
echo "$player_count" >"$player_count_file"

# Shutdown the EC2 instance if {player_count} and {prev_count} are both zero
if [[ "$player_count" -eq 0 && "$prev_count" -eq 0 ]]; then
    echo "No players online for two consecutive checks. Shutting down EC2 instance."
    sudo shutdown -h now
fi
