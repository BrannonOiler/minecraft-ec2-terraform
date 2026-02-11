# Minecraft Server on AWS Lightsail with Terraform

This Terraform project provisions a modded Minecraft server on EC2. Follow the setup below and the instructions in `docs/instructions.md` to set up the server and install Minecraft.

The mod used is [Homestead - A Cozy Survival Experience](https://www.curseforge.com/minecraft/modpacks/homestead-cozy). Feel free to modify the setup to use a different modpack or vanilla Minecraft.

## Features

- [x] EC2 instance with security group allowing Minecraft traffic (25565/tcp)
- [x] S3 backend for Terraform state management
- [x] Automated setup of Minecraft server software on the EC2 instance
- [x] A systemd timer job to automatically shut down the server when no players are online
- [x] Set whitelist permissions via Terraform variables
- [ ] A Discord bot for server status and management commands
- [ ] EBS snapshot lifecycle management for backups
- [ ] Modularize to allow multiple server instances with different mods/configurations
- [ ] Set up RCON for remote server management

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html)
- AWS account and credentials configured (e.g., via `aws configure`)

## Setup

<i>Follow this process first with only the `generate_ssh_key` resource uncommented to create the SSH key pair. Then uncomment the rest and run again to create the EC2 instance.</i>

1. Update variables in `variables.tf` (or create a `terraform.tfvars` file to override defaults)
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

- `aws_region`: AWS region to deploy the EC2 instance. Default: `us-east-2`
- `vpc_id`: VPC ID where the EC2 instance will be deployed. Default: `vpc-4bd37320` (us-east-2 main VPC)
- `subnet_id`: Subnet ID for the EC2 instance. Default: `subnet-bcf830d7` (us-east-2a subnet)
- `ami_id`: AMI ID for the EC2 instance. Default: `ami-024c678eb6c1de869` (Amazon Linux 2023 - kernel 6.12, ARM)
  - To use x86, update to `ami-0401b65de01e90bd8` (Amazon Linux 2023 - kernel 6.12, x86)
- `instance_type`: EC2 instance type for the Minecraft server. Default: `r7g.large` (2 vCPUs, 16 GiB RAM, memory optimized)
  - Other options: `t4g.xlarge` (4 vCPUs, 16 GiB RAM), `r8g.large` (2 vCPUs, 16 GiB RAM, newer gen)
- `instance_name`: Name for the Minecraft EC2 instance. Default: `minecraft-server-01`
- `ssh_key_pair_name`: Name of the EC2 key pair for SSH access. Default: `minecraft-server-01-key-pair`
- `ssh_key_pair_path`: Path to the SSH private key for accessing the EC2 instance. Default: `~/.ssh/personal-keys`
- `whitelist`: List of Minecraft usernames to whitelist on the server. Default: `[]`. Format:
  - Each entry is an object: `{ uuid = string, name = string }`

## Outputs

- `minecraft_connection_string`: Connection string for Minecraft client
- `public_ip`: Public IP address of the Minecraft server
- `rcon_password`: Generated RCON password for remote server management
