variable "fleet_name" { type = string }
variable "aws_region" { type = string }
variable "discord_public_key" { type = string }
variable "project_tag" { type = string }
variable "resource_name_prefix" { type = string }
variable "allowed_guild_id" {
  type = string

  validation {
    condition     = can(regex("^[0-9]{17,20}$", var.allowed_guild_id))
    error_message = "allowed_guild_id must be a Discord guild snowflake (17-20 digits)."
  }
}
