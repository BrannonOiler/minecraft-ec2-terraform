#!/bin/bash
set -u

mc_host="localhost"
mc_port="${MC_PORT:-25565}"
required_empty_checks="${MC_AUTO_SHUTDOWN_CHECKS:-2}"
empty_count_file="/tmp/mc-empty-check-count.txt"

previous_empty_checks=$(head -n 1 "$empty_count_file" 2>/dev/null || echo "0")
mcstatus_output=$(mcstatus "${mc_host}:${mc_port}" status 2>&1)
echo "$mcstatus_output"

# A failed status request could mean the server is still booting. Never treat it
# as an empty server, because that could shut the instance down during startup.
if ! player_count=$(echo "$mcstatus_output" | grep -oP 'players: \K\d+'); then
    echo "Could not determine player count; leaving the instance running."
    echo "0" >"$empty_count_file"
    exit 0
fi

echo "Current players: $player_count"
if [ "$player_count" -gt 0 ]; then
    echo "0" >"$empty_count_file"
    echo "Players are online; leaving the instance running."
    exit 0
fi

empty_checks=$((previous_empty_checks + 1))
echo "$empty_checks" >"$empty_count_file"

if [ "$empty_checks" -ge "$required_empty_checks" ]; then
    echo "No players for ${empty_checks} consecutive checks; shutting down."
    sudo shutdown -h now
else
    echo "No players online (${empty_checks}/${required_empty_checks}); checking again later."
fi
