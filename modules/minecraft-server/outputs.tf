locals {
  connection_public_ip = length(aws_eip.this) > 0 ? aws_eip.this["active"].public_ip : aws_instance.this.public_ip
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.this.id
}

output "root_volume_id" {
  description = "Disposable EC2 root volume ID."
  value       = aws_instance.this.root_block_device[0].volume_id
}

output "data_volume_id" {
  description = "Protected Minecraft data volume ID."
  value       = aws_ebs_volume.data.id
}

output "public_ip" {
  description = "Current public IP address, if one is assigned."
  value       = local.connection_public_ip == "" ? null : local.connection_public_ip
}

output "connection" {
  description = "Current public Minecraft host and port, if an address is assigned."
  value       = local.connection_public_ip == "" ? null : "${local.connection_public_ip}:${var.minecraft_port}"
}
