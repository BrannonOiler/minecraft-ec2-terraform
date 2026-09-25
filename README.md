# Minecraft fleet on EC2

This project manages multiple Minecraft servers as a Terraform fleet. Each
server has an EC2 instance, a current public IP or an explicitly retained
Elastic IP, an encrypted persistent world volume, profile-verified installation,
SSM-based configuration, scheduled snapshots, and Discord control through one
shared bot.

## Server model

Each `servers` entry selects a named `server_profiles` entry. Profiles provide
an immutable archive URL, SHA-256 digest, expected archive layout, Java
version, and start command. Terraform rejects unknown profiles; first boot
rejects an archive whose checksum or expected files do not match.

Copy [terraform.tfvars.example](terraform.tfvars.example) to a private tfvars
file and replace all placeholder values. Stable server keys are used in state,
tags, backups, and Discord commands; never rename one without a Terraform
`moved` declaration.

## Existing Homestead migration

The first rollout is intentionally two-stage:

1. Apply with `migrate_existing_data = false`. Review the plan to confirm that
   Homestead's EC2 instance, Elastic IP, and root volume are not replaced. This
   creates and attaches its encrypted data volume.
2. Take a manual snapshot of the existing root volume. Set
   `migrate_existing_data = true` and apply the reviewed plan during a quiet
   window. SSM stops Minecraft, copies and verifies the world, preserves the
   root-disk source as a rollback directory, mounts the data volume at
   `/srv/minecraft`, and restarts the server.

The data volume has Terraform deletion protection. Use the documented
decommission workflow before removing a server from the fleet.

## Discord

```text
/status
/start → choose a server
/stop → choose a server
```

`/stop` stops Minecraft through SSM, flushes filesystem writes, then shuts
the instance down. The bot accepts interactions only from the configured guild
when `discord_allowed_guild_id` is set, verifies signed requests, rejects stale
requests, and deduplicates interaction IDs for 15 minutes.

## Fleet whitelist

Put players who should access every current and future server in
`shared_whitelist`. To permit someone on only one server, add them to that
server's `additional_whitelist` instead. Each entry requires the player's
Minecraft UUID and name. Terraform delivers whitelist changes to running
servers through SSM without replacing an instance.

Use `shared_ops` for operators on every server and `additional_ops` for a
single-server operator. Minecraft settings belong in each server's optional
`server_settings` object. Defaults are PvP off, normal survival mode, four
players, an empty MOTD, view and simulation distance 10, flight off, and no
spawn protection. Use `mod_settings.simplebackups` only when a profile needs
to override its disabled-by-default in-game backup behavior.

Register guild commands after applying. This replaces the old `/mc` command
with `/start`, `/stop`, and `/status`:

```sh
./scripts/register-discord-commands.sh APPLICATION_ID BOT_TOKEN GUILD_ID
```

On Windows PowerShell:

```powershell
.\scripts\register-discord-commands.ps1 -ApplicationId APPLICATION_ID -BotToken BOT_TOKEN -GuildId GUILD_ID
```

Normal guild registration does not touch global commands. The Bash script can
replace every global command with `--replace-global` or remove only the legacy
global `/mc` command with `--remove-legacy-global`. The PowerShell script's
optional `-RemoveLegacyGlobal` switch removes global `/mc`, `/start`, `/stop`,
and `/status` commands after registering the guild commands. Both scripts load
the same command definitions from `scripts/discord-commands.json`.

## Operations

Use Systems Manager Session Manager for administrative access. Public SSH and
RCON are disabled by default; RCON passwords are neither created nor stored by
Terraform.

The data volume is the backup target. The shared DLM policy keeps one daily
09:00 UTC snapshot and one Sunday 09:00 UTC snapshot for each managed data
volume. Unless a server explicitly retains an Elastic IP, its public IP can
change after an EC2 stop/start; use Discord `/status` for the current address.
See [docs/instructions.md](docs/instructions.md) for migration, restore, and
decommission procedures.
