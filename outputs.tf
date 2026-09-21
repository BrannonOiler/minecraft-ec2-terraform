output "discord_bot_lambda_function_url" {
  description = "Discord interactions endpoint URL."
  value       = module.discord_bot_lambda.discord_bot_lambda_function_url
}

output "minecraft_connections" {
  description = "Minecraft connection address by stable server key."
  value       = { for key, server in module.minecraft_server : key => server.connection }
}

output "instance_ids" {
  description = "EC2 instance ID by stable server key."
  value       = { for key, server in module.minecraft_server : key => server.instance_id }
}

output "data_volume_ids" {
  description = "Protected Minecraft world volume by server key."
  value       = { for key, server in module.minecraft_server : key => server.data_volume_id }
}
