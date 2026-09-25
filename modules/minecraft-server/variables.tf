variable "server_key" {
  description = "Stable key used to identify this server throughout the fleet."
  type        = string
}

variable "display_name" {
  description = "Human-readable server name shown by the Discord bot."
  type        = string
}

variable "profile_name" {
  description = "Name of the selected immutable server profile."
  type        = string
}

variable "profile" {
  description = "Resolved server archive and installation settings."
  type = object({
    archive_url         = string
    archive_sha256      = string
    archive_directory   = string
    java_major          = number
    start_command       = string
    layout              = string
    forge_installer_jar = string
  })
}

variable "instance_name" {
  description = "Name assigned to the EC2 instance and related resources."
  type        = string
}

variable "ami_id" {
  description = "AMI used by the EC2 instance."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type used to run Minecraft."
  type        = string
}

variable "subnet_id" {
  description = "Subnet in which the instance and data volume are created."
  type        = string
}

variable "iam_instance_profile" {
  description = "IAM instance profile attached to the EC2 instance."
  type        = string
}

variable "security_group_ids" {
  description = "Security groups attached to the EC2 instance."
  type        = list(string)
}

variable "ssh_key_pair_name" {
  description = "Emergency-access EC2 key pair name."
  type        = string
}

variable "project_tag" {
  description = "Project tag used for fleet resource discovery."
  type        = string
}

variable "data_volume_size_gib" {
  description = "Persistent Minecraft data volume size in GiB."
  type        = number
}

variable "data_volume_kms_key_id" {
  description = "Optional KMS key used to encrypt the data volume."
  type        = string
  default     = null
  nullable    = true
}

variable "elastic_ip_enabled" {
  description = "Whether the instance retains an Elastic IP."
  type        = bool
}

variable "retired_data_volumes" {
  description = "Protected data volumes retained after controlled migrations."
  type = map(object({
    volume_id = string
    name      = string
  }))
}

variable "migrate_existing_data" {
  description = "Whether to migrate an existing root-volume server onto the data volume."
  type        = bool
}

variable "whitelist" {
  description = "Players allowed to join this server."
  type        = list(object({ uuid = string, name = string }))
}

variable "ops" {
  description = "Players granted operator privileges on this server."
  type        = list(object({ uuid = string, name = string }))
}

variable "java_min_memory" {
  description = "Minimum Java heap size."
  type        = string
}

variable "java_max_memory" {
  description = "Maximum Java heap size."
  type        = string
}

variable "server_settings" {
  description = "Minecraft properties managed by the fleet configuration."
  type = object({
    pvp                 = bool
    difficulty          = string
    game_mode           = string
    max_players         = number
    motd                = string
    view_distance       = number
    simulation_distance = number
    allow_flight        = bool
    spawn_protection    = number
  })
}

variable "simplebackups_settings" {
  description = "Settings managed in the optional Simple Backups mod configuration."
  type = object({
    enabled          = bool
    send_messages    = bool
    discord_messages = bool
  })
}

variable "minecraft_port" {
  description = "TCP port exposed by the Minecraft server."
  type        = number
}

variable "auto_shutdown_enabled" {
  description = "Whether the idle-server shutdown timer is enabled."
  type        = bool
}

variable "auto_shutdown_checks" {
  description = "Consecutive empty-player checks required before shutdown."
  type        = number
}

variable "auto_shutdown_period_min" {
  description = "Minutes between idle-server checks."
  type        = number
}
