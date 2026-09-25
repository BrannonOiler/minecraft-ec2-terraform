resource "aws_security_group" "minecraft_server_sg" {
  name = var.security_group_name
  # Preserve the deployed description so first-stage migration does not
  # replace the existing security group.
  description = "Allow Minecraft and SSH access"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = length(var.ssh_allowed_cidr_blocks) == 0 ? [] : [1]
    content {
      description = "Restricted administrative SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_allowed_cidr_blocks
    }
  }

  dynamic "ingress" {
    for_each = toset([for server in values(var.servers) : server.voice_chat_port])
    content {
      description = "Minecraft voice chat"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "udp"
      cidr_blocks = var.minecraft_allowed_cidr_blocks
    }
  }

  dynamic "ingress" {
    for_each = toset([for server in values(var.servers) : server.minecraft_port])
    content {
      description = "Minecraft"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = var.minecraft_allowed_cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
