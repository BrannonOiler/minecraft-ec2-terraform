# Fleet operations

## Deploy safely

1. Authenticate to AWS and run `terraform init` followed by a saved plan.
2. For the first fleet apply, require zero replacement of the existing
   Homestead instance, Elastic IP, or root volume.
3. Apply the initial configuration with Homestead's
   `migrate_existing_data = false`.
4. Confirm it is an SSM managed node and that the new data volume is attached.
5. Take a manual root-volume snapshot, set `migrate_existing_data = true`, and
   apply the second reviewed plan during a maintenance window.
6. Confirm `/srv/minecraft` is mounted, the old root-world directory remains
   as a dated rollback copy, Minecraft starts, and `/status` reports the
   expected address.

If migration fails before the symlink switch, the original root world remains
active. If it fails after the switch, stop Minecraft through SSM, repoint
`/home/ec2-user/minecraft-server` at the dated root backup, then restart the
service.

## Profile management

Store server archives somewhere durable, preferably a versioned private object
store. Compute its SHA-256 locally and record it in `server_profiles`. Do not
use expiring download links for new profiles. A changed profile checksum is a
new profile version; point servers at it only after validating it on a staging
server.

## Discord setup

Set the Discord application name, icon, and banner manually in the developer
portal to a fleet-oriented identity. Set its Interactions Endpoint URL to the
Terraform output, disable User Install, and register guild commands:

```sh
./scripts/register-discord-commands.sh APPLICATION_ID BOT_TOKEN GUILD_ID
```

The bot token belongs only in that interactive command. Never place it in a
tfvars file or repository.

## State backend follow-up

The current S3 backend intentionally retains its DynamoDB lock table during
the fleet migration. Move to the provider's newer S3 lock mechanism only after
the data migration is complete and two reviewed applies have succeeded without
drift. Treat that as a separate state-backend change with a backup of the state
object and an observed lock-free window.

## Restore and decommission

The shared DLM policy creates snapshots at 09:00 UTC. It retains one daily
recovery point and one additional Sunday recovery point for every managed data
volume.

To restore a world, create an EBS volume from a server's tagged snapshot,
attach it in the same availability zone, mount it through SSM, and verify the
world before replacing the active data volume.

To decommission a server, first run:

```sh
./scripts/decommission-server.sh SERVER_KEY VOLUME_ID AWS_REGION
```

Wait for and record the final snapshot ID. Then remove the server only after
intentionally disabling its data-volume lifecycle protection in a reviewed
change; this guard prevents an accidental map-entry deletion from destroying a
world.
