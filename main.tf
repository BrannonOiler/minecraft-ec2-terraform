module "minecraft_server" {
  for_each = var.servers
  source   = "./modules/minecraft-server"

  server_key               = each.key
  display_name             = each.value.display_name
  profile_name             = each.value.profile
  profile                  = local.resolved_server_profiles[each.value.profile]
  instance_name            = coalesce(each.value.instance_name, "${var.fleet_name}-${each.key}")
  ami_id                   = each.value.ami_id
  instance_type            = each.value.instance_type
  subnet_id                = each.value.subnet_id
  iam_instance_profile     = aws_iam_instance_profile.minecraft.name
  security_group_ids       = [aws_security_group.minecraft_server_sg.id]
  ssh_key_pair_name        = aws_key_pair.minecraft-server-key-pair.key_name
  project_tag              = var.project_tag
  data_volume_size_gib     = each.value.data_volume_size_gib
  data_volume_kms_key_id   = each.value.data_volume_kms_key_id
  elastic_ip_enabled       = each.value.elastic_ip_enabled
  retired_data_volumes     = each.value.retired_data_volumes
  migrate_existing_data    = each.value.migrate_existing_data
  whitelist                = local.server_whitelists[each.key]
  ops                      = local.server_ops[each.key]
  java_min_memory          = each.value.java_min_memory
  java_max_memory          = each.value.java_max_memory
  server_settings          = each.value.server_settings
  simplebackups_settings   = each.value.mod_settings.simplebackups
  minecraft_port           = each.value.minecraft_port
  auto_shutdown_enabled    = each.value.auto_shutdown_enabled
  auto_shutdown_checks     = each.value.auto_shutdown_checks
  auto_shutdown_period_min = each.value.auto_shutdown_period_min
}

module "ebs_backup" {
  source      = "./modules/ebs-backup"
  project_tag = var.project_tag
  volume_ids  = { for key, server in module.minecraft_server : key => server.data_volume_id }
}

module "discord_bot_lambda" {
  source = "./modules/discord-bot-lambda"

  fleet_name           = var.fleet_name
  discord_public_key   = var.discord_public_key
  allowed_guild_id     = var.discord_allowed_guild_id
  aws_region           = var.aws_region
  project_tag          = var.project_tag
  resource_name_prefix = coalesce(var.discord_resource_name_prefix, module.minecraft_server["homestead"].instance_id)
}
