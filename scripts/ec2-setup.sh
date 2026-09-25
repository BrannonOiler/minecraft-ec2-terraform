#!/bin/bash
set -euo pipefail

readonly config_file="/home/ec2-user/scripts/server-config.env"
readonly server_dir="/home/ec2-user/minecraft-server"

if [ ! -f "$config_file" ]; then
    echo "Missing server configuration: $config_file" >&2
    exit 1
fi
# shellcheck disable=SC1090
source "$config_file"

# Update only properties owned by the fleet configuration. awk avoids treating
# MOTD characters as sed syntax and preserves every unrelated server property.
set_server_property() {
    local key="$1"
    local value="$2"
    local properties_file="$3"
    local temporary_file
    temporary_file=$(mktemp)
    awk -v key="$key" -v value="$value" '
        $0 ~ "^" key "=" { print key "=" value; found = 1; next }
        { print }
        END { if (!found) print key "=" value }
    ' "$properties_file" >"$temporary_file"
    mv "$temporary_file" "$properties_file"
}

set_toml_boolean() {
    local key="$1"
    local value="$2"
    local toml_file="$3"
    if grep -q "^${key} = " "$toml_file"; then
        sed -i -E "s|^${key} = .*|${key} = ${value}|" "$toml_file"
    fi
}

ensure_java() {
    local java_package="java-${MC_JAVA_MAJOR}-amazon-corretto"
    if ! rpm -q "$java_package" >/dev/null 2>&1; then
        sudo dnf install -y "$java_package"
    fi
}

install_profile() {
    if [ -f "$server_dir/server.properties" ]; then
        return
    fi

    if [ -z "$MC_SERVER_ARCHIVE_SHA256" ]; then
        echo "Profile $MC_PROFILE_NAME has no archive SHA-256; refusing to bootstrap." >&2
        exit 1
    fi

    sudo dnf update -y
    sudo dnf install -y \
        awscli nc python3-pip rsync unzip wget
    sudo pip3 install mcstatus

    if [ ! -f /swapfile ]; then
        sudo fallocate -l 4G /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    fi

    mkdir -p "$server_dir"
    cd "$server_dir"

    if [[ "$MC_SERVER_ARCHIVE_URL" == s3://* ]]; then
        aws s3 cp "$MC_SERVER_ARCHIVE_URL" minecraft-server.zip
    else
        wget --https-only -O minecraft-server.zip "$MC_SERVER_ARCHIVE_URL"
    fi
    echo "${MC_SERVER_ARCHIVE_SHA256}  minecraft-server.zip" | sha256sum -c -
    unzip minecraft-server.zip -d .
    rm minecraft-server.zip

    if [ -n "$MC_ARCHIVE_DIRECTORY" ]; then
        if [ ! -d "$MC_ARCHIVE_DIRECTORY" ]; then
            echo "Profile $MC_PROFILE_NAME expected archive directory $MC_ARCHIVE_DIRECTORY." >&2
            exit 1
        fi
        shopt -s dotglob nullglob
        mv "$MC_ARCHIVE_DIRECTORY"/* .
        rmdir "$MC_ARCHIVE_DIRECTORY"
    fi

    case "$MC_PROFILE_LAYOUT" in
        legacy-start-sh)
            for required_file in start.sh variables.txt server.properties; do
                if [ ! -f "$required_file" ]; then
                    echo "Profile $MC_PROFILE_NAME is missing required file: $required_file" >&2
                    exit 1
                fi
            done
            ;;
        forge-installer)
            for required_file in "$MC_FORGE_INSTALLER_JAR" server.properties mods config; do
                if [ ! -e "$required_file" ]; then
                    echo "Forge profile $MC_PROFILE_NAME is missing required file or directory: $required_file" >&2
                    exit 1
                fi
            done
            java -jar "$MC_FORGE_INSTALLER_JAR" --installServer
            if [ ! -f run.sh ] || [ ! -f user_jvm_args.txt ]; then
                echo "Forge installer for $MC_PROFILE_NAME did not produce run.sh and user_jvm_args.txt." >&2
                exit 1
            fi
            chmod 0755 run.sh
            ;;
        *)
            echo "Unsupported profile layout: $MC_PROFILE_LAYOUT" >&2
            exit 1
            ;;
    esac

    echo "eula=true" >eula.txt
}

configure_java_memory() {
    case "$MC_PROFILE_LAYOUT" in
        legacy-start-sh)
            if [ ! -f "$server_dir/variables.txt" ]; then
                echo "Profile $MC_PROFILE_NAME has no variables.txt in the active server directory." >&2
                exit 1
            fi
            sed -i "s/^JAVA_ARGS=.*/JAVA_ARGS=\"-Xmx${MC_JAVA_MAX_MEMORY} -Xms${MC_JAVA_MIN_MEMORY}\"/" "$server_dir/variables.txt"
            ;;
        forge-installer)
            if [ ! -f "$server_dir/user_jvm_args.txt" ]; then
                echo "Forge profile $MC_PROFILE_NAME has no user_jvm_args.txt." >&2
                exit 1
            fi
            sed -i -E "s/^-Xms.*/-Xms${MC_JAVA_MIN_MEMORY}/; s/^-Xmx.*/-Xmx${MC_JAVA_MAX_MEMORY}/" "$server_dir/user_jvm_args.txt"
            grep -q "^-Xms${MC_JAVA_MIN_MEMORY}$" "$server_dir/user_jvm_args.txt" || echo "-Xms${MC_JAVA_MIN_MEMORY}" >>"$server_dir/user_jvm_args.txt"
            grep -q "^-Xmx${MC_JAVA_MAX_MEMORY}$" "$server_dir/user_jvm_args.txt" || echo "-Xmx${MC_JAVA_MAX_MEMORY}" >>"$server_dir/user_jvm_args.txt"
            ;;
        *)
            echo "Unsupported profile layout: $MC_PROFILE_LAYOUT" >&2
            exit 1
            ;;
    esac
}

configure_server_properties() {
    set_server_property "pvp" "$MC_PVP" "$server_dir/server.properties"
    set_server_property "difficulty" "$MC_DIFFICULTY" "$server_dir/server.properties"
    set_server_property "gamemode" "$MC_GAME_MODE" "$server_dir/server.properties"
    set_server_property "max-players" "$MC_MAX_PLAYERS" "$server_dir/server.properties"
    set_server_property "motd" "$MC_MOTD" "$server_dir/server.properties"
    set_server_property "view-distance" "$MC_VIEW_DISTANCE" "$server_dir/server.properties"
    set_server_property "simulation-distance" "$MC_SIMULATION_DISTANCE" "$server_dir/server.properties"
    set_server_property "allow-flight" "$MC_ALLOW_FLIGHT" "$server_dir/server.properties"
    set_server_property "spawn-protection" "$MC_SPAWN_PROTECTION" "$server_dir/server.properties"
    set_server_property "server-port" "$MC_PORT" "$server_dir/server.properties"
}

configure_simplebackups() {
    local simplebackups_config="$server_dir/config/simplebackups-common.toml"
    if [ -f "$simplebackups_config" ]; then
        set_toml_boolean "enabled" "$MC_SIMPLEBACKUPS_ENABLED" "$simplebackups_config"
        set_toml_boolean "sendMessages" "$MC_SIMPLEBACKUPS_SEND_MESSAGES" "$simplebackups_config"
        set_toml_boolean "mc2discord" "$MC_SIMPLEBACKUPS_DISCORD_MESSAGES" "$simplebackups_config"
    fi
}

write_systemd_units() {
    sudo tee /etc/systemd/system/minecraft.service >/dev/null <<EOF
[Unit]
Description=Minecraft Server (${MC_PROFILE_NAME})
After=network-online.target
Wants=network-online.target

[Service]
User=ec2-user
WorkingDirectory=/home/ec2-user/minecraft-server
ExecStart=${MC_START_COMMAND}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo tee /etc/systemd/system/auto-shutdown.service >/dev/null <<EOF
[Unit]
Description=Auto Shutdown Minecraft EC2 Instance

[Service]
Type=oneshot
User=ec2-user
EnvironmentFile=-/home/ec2-user/scripts/server-config.env
ExecStart=/home/ec2-user/scripts/auto-shutdown.sh
EOF

    sudo tee /etc/systemd/system/auto-shutdown.timer >/dev/null <<EOF
[Unit]
Description=Check whether an idle Minecraft server should stop

[Timer]
OnBootSec=10min
OnUnitActiveSec=${MC_AUTO_SHUTDOWN_PERIOD_MIN}min
Unit=auto-shutdown.service

[Install]
WantedBy=timers.target
EOF
}

configure_services() {
    sudo systemctl daemon-reload
    sudo systemctl enable minecraft.service
    if [ "$MC_AUTO_SHUTDOWN_ENABLED" = "true" ]; then
        sudo systemctl enable --now auto-shutdown.timer
    else
        sudo systemctl disable --now auto-shutdown.timer || true
    fi
}

main() {
    ensure_java
    install_profile
    configure_java_memory
    configure_server_properties
    configure_simplebackups
    write_systemd_units
    configure_services
}

main "$@"
