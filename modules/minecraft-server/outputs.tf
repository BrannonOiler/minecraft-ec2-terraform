locals {
  connection_public_ip = length(aws_eip.this) > 0 ? aws_eip.this["active"].public_ip : aws_instance.this.public_ip
}

output "instance_id" { value = aws_instance.this.id }
output "root_volume_id" { value = aws_instance.this.root_block_device[0].volume_id }
output "data_volume_id" { value = aws_ebs_volume.data.id }
output "public_ip" { value = local.connection_public_ip == "" ? null : local.connection_public_ip }
output "connection" {
  value = local.connection_public_ip == "" ? null : "${local.connection_public_ip}:${var.minecraft_port}"
}
