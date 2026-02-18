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
echo "Previous: $prev_count"
echo

# Use mcstatus to get current player count
mcstatus_output=$(mcstatus "$MC_HOST" status 2>&1)
echo "$mcstatus_output"
echo

#? Handle potential errors from mcstatus
if [[ "$mcstatus_output" == *"Error"* ]]; then
    echo "Error: $mcstatus_output"
    player_count=0
else
    player_count=$(echo "$mcstatus_output" | grep -oP 'players: \K\d+')
fi
echo "Current: $player_count"

# Update {player_count_file} with the current count
echo "$player_count" >"$player_count_file"
echo

# Shutdown the EC2 instance if {player_count} and {prev_count} are both zero
if [[ "$player_count" -eq 0 && "$prev_count" -eq 0 ]]; then
    echo "No players 2 checks in a row. Shutting down."
    sudo shutdown -h now
elif [[ "$player_count" -eq 0 ]]; then
    echo "No players online. Will check again before shutting down."
else
    echo "Players online. No shutdown needed."
fi
