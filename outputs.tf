output "minecraft_connection" {
  description = "Minecraft server connection string."
  value       = "${aws_eip.minecraft-server-eip.public_ip}:25565"
}

output "public_ip" {
  description = "Public IP address of the Minecraft server."
  value       = aws_eip.minecraft-server-eip.public_ip
}

output "rcon_password" {
  description = "RCON password for remote server management."
  value       = random_password.rcon_password.result
  sensitive   = true
}
