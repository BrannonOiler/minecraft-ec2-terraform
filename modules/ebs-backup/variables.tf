variable "instance_id" {
  description = "The ID of the EC2 instance whose root EBS volume will be backed up."
  type        = string
}

variable "volume_id" {
  description = "The ID of the EBS volume to back up."
  type        = string
}

variable "device_name" {
  description = "The device name of the EBS volume (e.g., /dev/xvda)."
  type        = string
  default     = "/dev/xvda"
}
