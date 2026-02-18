# Minecraft Server on AWS Lightsail with Terraform

This Terraform project provisions a modded Minecraft server on EC2. Follow the setup below and the instructions in `docs/instructions.md` to set up the server and install Minecraft.

The mod used is [Homestead - A Cozy Survival Experience](https://www.curseforge.com/minecraft/modpacks/homestead-cozy). Feel free to modify the setup to use a different modpack or vanilla Minecraft.

## Features

- EC2 instance with security group allowing Minecraft traffic (25565/tcp)
- S3 backend for Terraform state management
- Automated setup of Minecraft server software on the EC2 instance
- A systemd timer job to automatically shut down the server when no players are online
- Set whitelist permissions via Terraform variables
- Set up RCON for remote server management
- EBS snapshot lifecycle management for backups
- A Discord bot for server status and management commands

## Potential Future Enhancements

- Modularize to allow multiple server instances with different mods/configurations

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

- `ami_id`: AMI ID for the EC2 instance.
  - Default: `ami-024c678eb6c1de869` (Amazon Linux 2023 - kernel 6.12, ARM)
  - To use x86, update to `ami-0401b65de01e90bd8` (Amazon Linux 2023 - kernel 6.12, x86)
- `aws_region`: AWS region to deploy the EC2 instance.
  - Default: `us-east-2`
- `discord_public_key`: The public key from Discord for verifying incoming interactions.
  - Default: `<MY_DISCORD_PUBLIC_KEY>`
- `instance_name`: Name for the Minecraft EC2 instance.
  - Default: `minecraft-server-01`
- `instance_type`: EC2 instance type for the Minecraft server.
  - Default: `r7g.large` (2 vCPUs, 16 GiB RAM, $0.1071 hourly, memory optimized)
  - Other options: `t4g.xlarge` (4 vCPUs, 16 GiB RAM, $0.1344 hourly), `r8g.large` (2 vCPUs, 16 GiB RAM, $0.1178 hourly, newer gen)
- `ssh_key_pair_name`: Name of the EC2 key pair for SSH access.
  - Default: `minecraft-server-01-key-pair`
- `ssh_key_pair_path`: Path to the SSH private key for accessing the EC2 instance.
  - Default: `~/.ssh/personal-keys`
- `subnet_id`: Subnet ID for the EC2 instance.
  - Default: `subnet-bcf830d7` (us-east-2a subnet)
- `vpc_id`: VPC ID where the EC2 instance will be deployed.
  - Default: `vpc-4bd37320` (us-east-2 main VPC)
- `whitelist`: List of Minecraft usernames to whitelist on the server.
  - Default: `[]`
  - Format: Each entry is an object: `{ uuid = string, name = string }`

## Outputs

- `discord_bot_lambda_function_url`: URL of the Discord bot Lambda function.
- `minecraft_connection`: Minecraft server connection string.
- `public_ip`: Public IP address of the Minecraft server.
- `rcon_password`: RCON password for remote server management.
