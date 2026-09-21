#!/bin/bash
set -euo pipefail

if [ $# -ne 3 ]; then
    echo "Usage: $0 <SERVER_KEY> <VOLUME_ID> <AWS_REGION>" >&2
    exit 1
fi

server_key="$1"
volume_id="$2"
region="$3"

snapshot_id=$(aws ec2 create-snapshot \
    --region "$region" \
    --volume-id "$volume_id" \
    --description "Final Minecraft world snapshot for ${server_key}" \
    --tag-specifications "ResourceType=snapshot,Tags=[{Key=MinecraftServer,Value=${server_key}},{Key=SnapshotPurpose,Value=decommission}]" \
    --query 'SnapshotId' \
    --output text)

aws ec2 wait snapshot-completed --region "$region" --snapshot-ids "$snapshot_id"
echo "Final snapshot complete: $snapshot_id"
echo "The Terraform data-volume guard remains enabled. Remove it only in a reviewed decommission change."
