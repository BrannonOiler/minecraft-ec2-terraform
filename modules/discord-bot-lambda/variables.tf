variable "aws_region" {
  description = "The AWS region where the EC2 instance and Lambda function are located."
  type        = string
  default     = "us-east-2"
}

variable "discord_public_key" {
  description = "The public key from Discord for verifying incoming interactions."
  type        = string
}

variable "instance_id" {
  description = "The ID of the EC2 instance whose root EBS volume will be backed up."
  type        = string
}
