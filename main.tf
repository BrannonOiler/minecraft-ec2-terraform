terraform {
  #? Store state in S3
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

###! THIS SECTION MUST BE APPLIED FIRST ###
#? Generate SSH key pair locally (if not already present)
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
###! END SECTION ###

#? Create EC2 key pair using the generated public key
resource "aws_key_pair" "minecraft-server-key-pair" {
  key_name   = var.ssh_key_pair_name
  public_key = file("${var.ssh_key_pair_path}/${var.ssh_key_pair_name}.pub")
  depends_on = [null_resource.generate_ssh_key]
}

#? Create Security Group for Minecraft and SSH
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

  ingress {
    description = "Minecraft RCON Port"
    from_port   = 25575
    to_port     = 25575
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

#? Convert ${whitelist} variable to whitelist.json that can be copied to EC2 instance
resource "local_file" "whitelist_json" {
  content  = templatefile("${path.module}/templates/whitelist.tpl", { whitelist = var.whitelist })
  filename = "${path.module}/tmp/whitelist.json"
}

#? Convert ${whitelist} variable to ops.json that can be copied to EC2 instance
#! For now, all whitelisted players are also ops (level 2)
resource "local_file" "ops_json" {
  content  = templatefile("${path.module}/templates/ops.tpl", { ops = var.whitelist })
  filename = "${path.module}/tmp/ops.json"
}

#? Generate a password for RCON (remote console) access to the Minecraft server
resource "random_password" "rcon_password" {
  length  = 16
  special = true
}

#? Create EC2 instance for Minecraft server
resource "aws_instance" "minecraft-server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.minecraft-server-key-pair.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.minecraft_server_sg.id]

  tags = {
    Name = var.instance_name
  }

  #? Create ~/scripts directory on the EC2 instance for setup scripts
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /home/ec2-user/scripts"
    ]
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${var.ssh_key_pair_path}/${var.ssh_key_pair_name}")
      host        = self.public_ip
    }
  }

  #? Copy setup scripts from scripts/ directory on local machine to ~/scripts on the EC2 instance
  provisioner "file" {
    source      = "scripts/"
    destination = "/home/ec2-user/scripts"
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${var.ssh_key_pair_path}/${var.ssh_key_pair_name}")
      host        = self.public_ip
    }
  }

  #? Run the EC2 setup script and other necessary commands to set up the Minecraft server
  provisioner "remote-exec" {
    inline = [
      #? Make the setup script executable
      "chmod +x /home/ec2-user/scripts/*",
      #? Run the setup script to install Java, download and configure the Minecraft server, set up the auto-shutdown service, etc.
      "cd ~ && /home/ec2-user/scripts/ec2-setup.sh",
      #? Enable and set the RCON password in the server.properties file
      "sed -i 's/^enable-rcon=.*/enable-rcon=true/' /home/ec2-user/minecraft-server/server.properties",
      "sed -i 's/^rcon.password=.*/rcon.password=${random_password.rcon_password.result}/' /home/ec2-user/minecraft-server/server.properties"
    ]
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${var.ssh_key_pair_path}/${var.ssh_key_pair_name}")
      host        = self.public_ip
    }
  }

  #? Copy the generated whitelist.json file to the EC2 instance
  provisioner "file" {
    source      = local_file.whitelist_json.filename
    destination = "/home/ec2-user/minecraft-server/whitelist.json"
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${var.ssh_key_pair_path}/${var.ssh_key_pair_name}")
      host        = self.public_ip
    }
  }

  #? Copy the generated ops.json file to the EC2 instance
  provisioner "file" {
    source      = local_file.ops_json.filename
    destination = "/home/ec2-user/minecraft-server/ops.json"
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${var.ssh_key_pair_path}/${var.ssh_key_pair_name}")
      host        = self.public_ip
    }
  }

  #? Restart the Minecraft server to apply whitelist and ops changes
  provisioner "remote-exec" {
    inline = [
      "sudo systemctl restart minecraft.service"
    ]
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${var.ssh_key_pair_path}/${var.ssh_key_pair_name}")
      host        = self.public_ip
    }
  }
}

#? Create an Elastic IP for the Minecraft server
resource "aws_eip" "minecraft-server-eip" {
  instance = aws_instance.minecraft-server.id
}

#? EBS Backup Lifecycle Policy Module
module "ebs_backup" {
  source      = "./modules/ebs-backup"
  instance_id = aws_instance.minecraft-server.id
  volume_id   = aws_instance.minecraft-server.root_block_device[0].volume_id
  device_name = "/dev/xvda"
}

#? Discord Bot Lambda Function Module
module "discord_bot_lambda" {
  source             = "./modules/discord-bot-lambda"
  discord_public_key = var.discord_public_key
  instance_id        = aws_instance.minecraft-server.id
  aws_region         = var.aws_region
}
