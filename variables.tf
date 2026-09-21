variable "aws_region" {
  description = "AWS region for the Minecraft fleet."
  type        = string
  default     = "us-east-2"
}

variable "fleet_name" {
  description = "Stable, lowercase identifier for shared fleet resources."
  type        = string
  default     = "minecraft-fleet"
}

variable "project_tag" {
  description = "Project tag used to discover Minecraft resources."
  type        = string
  default     = "minecraft-server"
}

variable "discord_public_key" {
  description = "Discord application public key used to verify interaction signatures."
  type        = string
}

variable "discord_allowed_guild_id" {
  description = "The single Discord guild allowed to use the bot."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{17,20}$", var.discord_allowed_guild_id))
    error_message = "discord_allowed_guild_id must be a Discord guild snowflake (17-20 digits)."
  }
}

variable "discord_resource_name_prefix" {
  description = "Stable Lambda/IAM name prefix. Leave null for the first migration to preserve existing names, then set to fleet_name in a later reviewed apply."
  type        = string
  default     = null
  nullable    = true
}

variable "vpc_id" {
  description = "VPC containing the Minecraft fleet."
  type        = string
}

variable "ssh_key_pair_name" {
  description = "Existing EC2 key pair name retained for emergency access."
  type        = string
  default     = "minecraft-server-01-key-pair"
}

variable "ssh_key_pair_path" {
  description = "Local path that holds the retained emergency SSH key pair."
  type        = string
  default     = "~/.ssh/personal-keys"
}

variable "ssh_key_pair_public_key" {
  description = "Existing SSH public key. Set this when the local .pub file is unavailable."
  type        = string
  default     = null
  nullable    = true
}

variable "security_group_name" {
  description = "Existing security group name retained during the fleet migration."
  type        = string
  default     = "minecraft-server-01-sg"
}

variable "ssh_allowed_cidr_blocks" {
  description = "CIDRs allowed to SSH. Empty disables public SSH."
  type        = list(string)
  default     = []
}

variable "minecraft_allowed_cidr_blocks" {
  description = "CIDRs allowed to connect to Minecraft and voice chat."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "server_profiles" {
  description = "Versioned, checksum-verified Minecraft server distributions."
  type = map(object({
    archive_url          = optional(string, "")
    archive_sha256       = string
    archive_directory    = string
    java_major           = optional(number, 17)
    start_command        = optional(string, "/bin/bash start.sh")
    layout               = optional(string, "legacy-start-sh")
    forge_installer_jar  = optional(string, "")
    artifact_source_path = optional(string, null)
  }))
  default = {}

  validation {
    condition = alltrue([
      for profile in values(var.server_profiles) :
      profile.archive_sha256 == "" || can(regex("^[a-fA-F0-9]{64}$", profile.archive_sha256))
    ])
    error_message = "Each profile archive_sha256 must be a SHA-256 hex digest. Empty is permitted only for the migrated server that already has files installed."
  }

  validation {
    condition = alltrue([
      for profile in values(var.server_profiles) :
      contains(["legacy-start-sh", "forge-installer"], profile.layout) &&
      (profile.layout != "forge-installer" || profile.forge_installer_jar != "")
    ])
    error_message = "Profiles must use a supported layout; forge-installer profiles require forge_installer_jar."
  }
}

variable "shared_whitelist" {
  description = "Minecraft accounts whitelisted on every server in the fleet. Use additional_whitelist on an individual server for exceptions."
  type = list(object({
    uuid = string
    name = string
  }))
  default = []

  validation {
    condition     = length(distinct([for player in var.shared_whitelist : player.uuid])) == length(var.shared_whitelist)
    error_message = "shared_whitelist cannot contain the same UUID more than once."
  }

  validation {
    condition = alltrue([
      for player in var.shared_whitelist :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", player.uuid))
    ])
    error_message = "Every shared_whitelist UUID must be a standard Minecraft UUID."
  }
}

variable "shared_ops" {
  description = "Minecraft accounts granted operator status on every server in the fleet. Use additional_ops on an individual server for exceptions."
  type = list(object({
    uuid = string
    name = string
  }))
  default = []

  validation {
    condition     = length(distinct([for player in var.shared_ops : player.uuid])) == length(var.shared_ops)
    error_message = "shared_ops cannot contain the same UUID more than once."
  }

  validation {
    condition = alltrue([
      for player in var.shared_ops :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", player.uuid))
    ])
    error_message = "Every shared_ops UUID must be a standard Minecraft UUID."
  }
}

variable "servers" {
  description = "Minecraft servers keyed by stable Discord-friendly identifiers."
  type = map(object({
    display_name           = string
    profile                = string
    instance_name          = optional(string)
    ami_id                 = string
    instance_type          = string
    subnet_id              = string
    data_volume_size_gib   = optional(number, 40)
    data_volume_kms_key_id = optional(string)
    # Set only while retaining an existing address during a controlled transition.
    elastic_ip_enabled = optional(bool, false)
    retired_data_volumes = optional(map(object({
      volume_id = string
      name      = string
    })), {})
    migrate_existing_data = optional(bool, false)
    additional_whitelist = optional(list(object({
      uuid = string
      name = string
    })), [])
    additional_ops = optional(list(object({
      uuid = string
      name = string
    })), [])
    server_settings = optional(object({
      pvp                 = optional(bool, false)
      difficulty          = optional(string, "normal")
      game_mode           = optional(string, "survival")
      max_players         = optional(number, 4)
      motd                = optional(string, "")
      view_distance       = optional(number, 10)
      simulation_distance = optional(number, 10)
      allow_flight        = optional(bool, false)
      spawn_protection    = optional(number, 0)
    }), {})
    mod_settings = optional(object({
      simplebackups = optional(object({
        enabled          = optional(bool, false)
        send_messages    = optional(bool, false)
        discord_messages = optional(bool, false)
      }), {})
    }), {})
    java_min_memory          = optional(string, "8G")
    java_max_memory          = optional(string, "12G")
    minecraft_port           = optional(number, 25565)
    voice_chat_port          = optional(number, 25564)
    auto_shutdown_enabled    = optional(bool, true)
    auto_shutdown_checks     = optional(number, 2)
    auto_shutdown_period_min = optional(number, 5)
  }))

  validation {
    condition = alltrue([
      for key in keys(var.servers) : can(regex("^[a-z0-9][a-z0-9-]{0,31}$", key))
    ])
    error_message = "Server keys must be 1-32 lowercase letters, digits, or hyphens, and start with a letter or digit."
  }

  validation {
    condition     = contains(keys(var.servers), "homestead")
    error_message = "The fleet must retain the homestead key while migrating the existing server."
  }

  validation {
    condition = alltrue([
      for server in values(var.servers) :
      length(distinct([for player in server.additional_whitelist : player.uuid])) == length(server.additional_whitelist)
    ])
    error_message = "A server's additional_whitelist cannot contain the same UUID more than once."
  }

  validation {
    condition = alltrue(flatten([
      for server in values(var.servers) : [
        for player in server.additional_whitelist :
        can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", player.uuid))
      ]
    ]))
    error_message = "Every additional_whitelist UUID must be a standard Minecraft UUID."
  }

  validation {
    condition = alltrue([
      for server in values(var.servers) :
      length(distinct([for player in server.additional_ops : player.uuid])) == length(server.additional_ops)
    ])
    error_message = "A server's additional_ops cannot contain the same UUID more than once."
  }

  validation {
    condition = alltrue(flatten([
      for server in values(var.servers) : [
        for player in server.additional_ops :
        can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", player.uuid))
      ]
    ]))
    error_message = "Every additional_ops UUID must be a standard Minecraft UUID."
  }

  validation {
    condition = alltrue([
      for server in values(var.servers) :
      contains(["peaceful", "easy", "normal", "hard"], server.server_settings.difficulty) &&
      contains(["survival", "creative", "adventure", "spectator"], server.server_settings.game_mode) &&
      server.server_settings.max_players >= 1 && server.server_settings.max_players <= 100 &&
      server.server_settings.view_distance >= 2 && server.server_settings.view_distance <= 32 &&
      server.server_settings.simulation_distance >= 2 && server.server_settings.simulation_distance <= 32 &&
      server.server_settings.spawn_protection >= 0 && server.server_settings.spawn_protection <= 128
    ])
    error_message = "server_settings values must use supported Minecraft modes and safe player, distance, and spawn-protection ranges."
  }
}
