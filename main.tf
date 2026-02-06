terraform {
  # Store state in S3
  backend "s3" {
    bucket         = "tf-state-v5736ps3czzv"
    key            = "mc-homestead-server/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "tf-locks-v5736ps3czzv"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
  
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project = "minecraft-server"
    }
  }
}

### THIS SECTION MUST BE APPLIED FIRST ###
# Generate SSH key pair locally (if not already present)
resource "null_resource" "generate_ssh_key" {
  provisioner "local-exec" {
    command = <<EOT
      mkdir -p "${pathexpand(var.ssh_key_pair_path)}"
      if [ ! -f "${pathexpand(var.ssh_key_pair_path)}/${var.ssh_key_pair_name}" ]; then
        ssh-keygen -t rsa -b 4096 -f "${pathexpand(var.ssh_key_pair_path)}/${var.ssh_key_pair_name}" -N ""
      fi
    EOT
  }
}
### END SECTION ###

# Create EC2 key pair using the generated public key
resource "aws_key_pair" "minecraft-server-key-pair" {
  key_name   = var.ssh_key_pair_name
  public_key = file("${var.ssh_key_pair_path}/${var.ssh_key_pair_name}.pub")
  depends_on = [null_resource.generate_ssh_key]
}

# Create Security Group for Minecraft and SSH
resource "aws_security_group" "minecraft_server_sg" {
  name        = "${var.instance_name}-sg"
  description = "Allow Minecraft and SSH access"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Minecraft Voice Chat Port"
    from_port   = 25564
    to_port     = 25564
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Default Minecraft Port"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = var.instance_name
  }
}

# Create EC2 instance for Minecraft server
resource "aws_instance" "minecraft-server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.minecraft-server-key-pair.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.minecraft_server_sg.id]

  tags = {
    Name = var.instance_name
  }
}

# Create an Elastic IP for the Minecraft server
resource "aws_eip" "minecraft-server-eip" {
  instance = aws_instance.minecraft-server.id
}


