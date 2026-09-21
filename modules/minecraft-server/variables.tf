variable "server_key" { type = string }
variable "display_name" { type = string }
variable "profile_name" { type = string }
variable "profile" {
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
variable "instance_name" { type = string }
variable "ami_id" { type = string }
variable "instance_type" { type = string }
variable "subnet_id" { type = string }
variable "iam_instance_profile" { type = string }
variable "security_group_ids" { type = list(string) }
variable "ssh_key_pair_name" { type = string }
variable "project_tag" { type = string }
variable "data_volume_size_gib" { type = number }
variable "data_volume_kms_key_id" {
  type     = string
  default  = null
  nullable = true
}
variable "elastic_ip_enabled" { type = bool }
variable "retired_data_volumes" {
  type = map(object({
    volume_id = string
    name      = string
  }))
}
variable "migrate_existing_data" { type = bool }
variable "whitelist" { type = list(object({ uuid = string, name = string })) }
variable "ops" { type = list(object({ uuid = string, name = string })) }
variable "java_min_memory" { type = string }
variable "java_max_memory" { type = string }
variable "server_settings" {
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
  type = object({
    enabled          = bool
    send_messages    = bool
    discord_messages = bool
  })
}
variable "minecraft_port" { type = number }
variable "auto_shutdown_enabled" { type = bool }
variable "auto_shutdown_checks" { type = number }
variable "auto_shutdown_period_min" { type = number }
