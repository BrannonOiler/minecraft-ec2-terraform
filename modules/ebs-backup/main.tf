#* EBS Backup Lifecycle Policy Module
#* - provisions IAM resources and a DLM lifecycle policy to snapshot an EBS volume on a schedule.

#? IAM Assume Role Policy for DLM
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

#? IAM Role for DLM
resource "aws_iam_role" "dlm_lifecycle_role" {
  name               = "dlm-lifecycle-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

#? IAM Policy for DLM
data "aws_iam_policy_document" "dlm_lifecycle" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateSnapshot",
      "ec2:CreateSnapshots",
      "ec2:DeleteSnapshot",
      "ec2:DescribeInstances",
      "ec2:DescribeVolumes",
      "ec2:DescribeSnapshots",
    ]
    resources = ["*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:aws:ec2:*::snapshot/*"]
  }
}

#? Attach IAM Policy to Role
resource "aws_iam_role_policy" "dlm_lifecycle" {
  name   = "dlm-lifecycle-policy"
  role   = aws_iam_role.dlm_lifecycle_role.id
  policy = data.aws_iam_policy_document.dlm_lifecycle.json
}

#? Tag the EBS volume for snapshot targeting
resource "aws_ec2_tag" "snapshot_tag" {
  resource_id = var.volume_id
  key         = "Snapshot"
  value       = "true"
}

#? DLM Lifecycle Policy for EBS Snapshots (powers of 2 retention)
resource "aws_dlm_lifecycle_policy" "snapshots" {
  description        = "EBS snapshot policy for Minecraft server volume"
  execution_role_arn = aws_iam_role.dlm_lifecycle_role.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]
    target_tags = {
      Snapshot = "true"
    }

    #? 1 and 2 day retention
    schedule {
      name = "1 and 2 day snapshot"
      create_rule {
        cron_expression = "cron(0 9 ? * * *)"
      }
      retain_rule {
        count = 2
      }
      tags_to_add = { SnapshotCreator = "DLM" }
      copy_tags   = false
    }

    #? 4 and 8 day retention
    schedule {
      name = "4 and 8 day snapshot"
      create_rule {
        cron_expression = "cron(0 9 */4 * ? *)"
      }
      retain_rule {
        count = 2
      }
      tags_to_add = { SnapshotCreator = "DLM" }
      copy_tags   = false
    }

    #? 16 and 32 day retention
    schedule {
      name = "16 and 32 day snapshot"
      create_rule {
        cron_expression = "cron(0 9 */16 * ? *)"
      }
      retain_rule {
        count = 2
      }
      tags_to_add = { SnapshotCreator = "DLM" }
      copy_tags   = false
    }
  }
}


