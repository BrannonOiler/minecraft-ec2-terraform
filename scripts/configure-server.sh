#!/bin/bash
set -euo pipefail

config_dir="/opt/minecraft-fleet"
config_file="${config_dir}/server-config.env"
data_volume_id="${DATA_VOLUME_ID:?DATA_VOLUME_ID is required}"
migrate_existing_data="${MIGRATE_EXISTING_DATA:-false}"
server_link="/home/ec2-user/minecraft-server"
data_dir="/srv/minecraft"
lock_file="/var/lock/minecraft-fleet-configure.lock"

exec 9>"$lock_file"
flock -n 9 || exit 0

# shellcheck disable=SC1090
source "$config_file"
mkdir -p /var/lib/minecraft-fleet

desired_hash=$(cat \
    "$config_file" \
    "$config_dir/whitelist.json" \
    "$config_dir/ops.json" \
    "$config_dir/ec2-setup.sh" \
    "$config_dir/auto-shutdown.sh" | \
    { cat; printf '\n%s\n%s\n' "$data_volume_id" "$migrate_existing_data"; } | \
    sha256sum | awk '{print $1}')
if [ -f /var/lib/minecraft-fleet/config.hash ] && \
   [ "$(cat /var/lib/minecraft-fleet/config.hash)" = "$desired_hash" ]; then
    exit 0
fi

find_data_device() {
    local compact_id="${data_volume_id//-/}"
    local candidate=""
    for _ in $(seq 1 60); do
        candidate=$(readlink -f "/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${compact_id}" 2>/dev/null || true)
        if [ -b "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi

        candidate=$(lsblk -pnro NAME,SERIAL | awk -v id="$compact_id" '$2 == id { print $1; exit }')
        if [ -b "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi

        for candidate in /dev/xvdf /dev/sdf; do
            if [ -b "$candidate" ]; then
                printf '%s\n' "$candidate"
                return 0
            fi
        done
        sleep 5
    done
    return 1
}

mount_data_volume() {
    local device
    device=$(find_data_device) || {
        echo "Data volume ${data_volume_id} did not appear within five minutes." >&2
        exit 1
    }

    if ! blkid "$device" >/dev/null 2>&1; then
        mkfs.ext4 -F -L minecraft-data "$device"
    fi

    install -d -m 0755 "$data_dir"
    local uuid
    uuid=$(blkid -s UUID -o value "$device")
    grep -q " $data_dir " /etc/fstab || echo "UUID=${uuid} ${data_dir} ext4 defaults,nofail 0 2" >>/etc/fstab
    mountpoint -q "$data_dir" || mount "$data_dir"
    chown ec2-user:ec2-user "$data_dir"
}

is_existing_root_server() {
    [ -d "$server_link" ] && [ ! -L "$server_link" ] && [ -f "$server_link/server.properties" ]
}

if is_existing_root_server && [ "$migrate_existing_data" != "true" ]; then
    active_dir="$server_link"
else
    mount_data_volume

    if is_existing_root_server && [ ! -f /var/lib/minecraft-fleet/data-migrated ]; then
        dnf install -y rsync
        systemctl stop minecraft.service || true
        rsync -aHAX --numeric-ids "$server_link/" "$data_dir/"
        test -z "$(rsync -aHAXn --delete --numeric-ids "$server_link/" "$data_dir/")"
        mv "$server_link" "${server_link}.root-backup-$(date +%Y%m%d%H%M%S)"
        ln -s "$data_dir" "$server_link"
        touch /var/lib/minecraft-fleet/data-migrated
    elif [ ! -e "$server_link" ]; then
        ln -s "$data_dir" "$server_link"
    fi
    active_dir="$data_dir"
fi

install -d -o ec2-user -g ec2-user /home/ec2-user/scripts
install -m 0700 -o ec2-user -g ec2-user "$config_dir/ec2-setup.sh" /home/ec2-user/scripts/ec2-setup.sh
install -m 0700 -o ec2-user -g ec2-user "$config_dir/auto-shutdown.sh" /home/ec2-user/scripts/auto-shutdown.sh
install -m 0600 -o ec2-user -g ec2-user "$config_file" /home/ec2-user/scripts/server-config.env

# The setup script is deliberately idempotent: on an installed server it
# refreshes the systemd units and timer settings; on a new server it also
# verifies and installs the selected profile.
sudo -u ec2-user -H /home/ec2-user/scripts/ec2-setup.sh

install -m 0644 -o ec2-user -g ec2-user "$config_dir/whitelist.json" "$active_dir/whitelist.json"
install -m 0644 -o ec2-user -g ec2-user "$config_dir/ops.json" "$active_dir/ops.json"

sed -i 's/^enable-rcon=.*/enable-rcon=false/' "$active_dir/server.properties"
sed -i '/^rcon.password=/d' "$active_dir/server.properties"
sed -i 's/^enforce-whitelist=.*/enforce-whitelist=true/' "$active_dir/server.properties"
sed -i 's/^white-list=.*/white-list=true/' "$active_dir/server.properties"

systemctl daemon-reload
systemctl enable minecraft.service auto-shutdown.timer
systemctl restart minecraft.service
printf '%s\n' "$desired_hash" >/var/lib/minecraft-fleet/config.hash
