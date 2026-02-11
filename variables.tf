variable "aws_region" {
  description = "AWS region to deploy the EC2 instance."
  type        = string
  default     = "us-east-2"
}

variable "vpc_id" {
  description = "VPC ID where the EC2 instance will be deployed."
  type        = string
  default     = "vpc-4bd37320" # us-east-2 main VPC
}

variable "subnet_id" {
  description = "Subnet ID for the EC2 instance."
  type        = string
  default     = "subnet-bcf830d7" # us-east-2a subnet
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance."
  type        = string
  default     = "ami-024c678eb6c1de869" # Amazon Linux 2023 - kernel 6.12 (ARM)
  # default     = "ami-0401b65de01e90bd8" # Amazon Linux 2023 - kernel 6.12 (x86)
}

variable "instance_type" {
  description = "EC2 instance type for the Minecraft server."
  type        = string
  default     = "r7g.large" # 2 vCPUs, 16 GiB RAM, $0.1071 hourly, memory optimized
  ## Other options:
  # default     = "t4g.xlarge" # 4 vCPUs16, GiB RAM, $0.1344 hourly
  # default    = "r8g.large" # 2 vCPUs, 16 GiB RAM, $0.1178 hourly, memory optimized, newer gen
}

variable "instance_name" {
  description = "Name for the Minecraft EC2 instance."
  type        = string
  default     = "minecraft-server-01"
}

variable "ssh_key_pair_name" {
  description = "Name of the EC2 key pair for SSH access."
  type        = string
  default     = "minecraft-server-01-key-pair"
}

variable "ssh_key_pair_path" {
  description = "Path to the SSH private key for accessing the EC2 instance."
  default     = "~/.ssh/personal-keys"
}

variable "whitelist" {
  description = "List of Minecraft usernames to whitelist on the server."
  type = list(object({
    uuid = string
    name = string
  }))
  default = []
}
