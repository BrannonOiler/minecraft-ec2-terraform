# Minecraft Server on AWS Lightsail with Terraform

This Terraform project provisions a modded Minecraft server on EC2. Follow the instructions in `docs/instructions.md` to set up the server and install Minecraft.

The mod is [Homestead - A Cozy Survival Experience](https://www.curseforge.com/minecraft/modpacks/homestead-cozy).

## Features

- [x] EC2 instance with security group allowing Minecraft traffic (25565/tcp)
- [x] S3 backend for Terraform state management
- [ ] Automated setup of Minecraft server software on the EC2 instance
- [ ] A Discord bot for server status and management commands
- [ ] A cron job to automatically shut down the server when no players are online
- [ ] EBS snapshot lifecycle management for backups
- [ ] Add admin settings (for everyone) and server password
- [ ] Modularize to allow multiple server instances with different mods/configurations

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html)
- AWS account and credentials configured (e.g., via `aws configure`)

## Setup

<i>Follow this process first with only the `generate_ssh_key` resource uncommented to create the SSH key pair. Then uncomment the rest and run again to create the EC2 instance.</i>

1. Update variables in `variables.tf` as needed
2. Initialize Terraform:
   ```sh
   terraform init
   ```
3. Apply the configuration:
   ```sh
   terraform apply
   ```
4. Note the output for the public IP and Minecraft connection string.

## Variables

- `aws_region`: AWS region to deploy the EC2 instance (default: `us-east-2`)
- `vpc_id`: VPC ID where the EC2 instance will be deployed (default: `vpc-4bd37320`)
- `subnet_id`: Subnet ID for the EC2 instance (default: `subnet-bcf830d7`)
- `ami_id`: AMI ID for the EC2 instance (default: `ami-024c678eb6c1de869`)
- `instance_type`: EC2 instance type for the Minecraft server (default: `r7g.large`)
- `instance_name`: Name for the Minecraft EC2 instance (default: `minecraft-server-01`)
- `ssh_key_pair_name`: Name of the EC2 key pair for SSH access (default: `minecraft-server-01-key-pair`)
- `ssh_key_pair_path`: Path to the SSH private key for accessing the EC2 instance (default: `~/.ssh/personal-keys`)

## Outputs

- `public_ip`: Public IP address of the Minecraft server
- `minecraft_connection_string`: Connection string for Minecraft client
