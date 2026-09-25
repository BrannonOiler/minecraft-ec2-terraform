variable "fleet_name" {
  description = "Stable name used for shared fleet resources."
  type        = string
}

variable "aws_region" {
  description = "AWS region containing the managed Minecraft fleet."
  type        = string
}

variable "discord_public_key" {
  description = "Discord application public key used to verify interactions."
  type        = string
}

variable "project_tag" {
  description = "Project tag used to discover manageable EC2 instances."
  type        = string
}

variable "resource_name_prefix" {
  description = "Prefix retained across the Lambda and IAM resource names."
  type        = string
}

variable "allowed_guild_id" {
  description = "Discord guild allowed to use the bot."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{17,20}$", var.allowed_guild_id))
    error_message = "allowed_guild_id must be a Discord guild snowflake (17-20 digits)."
  }
}
