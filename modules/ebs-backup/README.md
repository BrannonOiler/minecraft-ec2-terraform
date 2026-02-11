# EBS Backup Lifecycle Policy Module

## Inputs

- `instance_id`: The EC2 instance ID whose root EBS volume will be backed up.
- `volume_id`: The EBS volume ID to back up.
- `device_name`: The device name of the EBS volume (default: `/dev/xvda`).

## Outputs

- `dlm_policy_arn`: The ARN of the created DLM lifecycle policy.

## Description

This module provisions the necessary IAM resources and a DLM lifecycle policy to snapshot an EBS volume on a schedule (1, 4, 16, 32 days retention, powers of 2). The volume is tagged for targeting by the policy.

## Example Usage

```
module "ebs_backup" {
  source      = "./modules/ebs-backup"
  instance_id = aws_instance.minecraft-server.id
  volume_id   = aws_instance.minecraft-server.root_block_device[0].volume_id
  device_name = "/dev/xvda"
}
```
