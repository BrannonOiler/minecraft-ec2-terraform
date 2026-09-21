terraform {
  backend "s3" {
    bucket         = "tf-state-v5736ps3czzv"
    key            = "mc-homestead-server/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "tf-locks-v5736ps3czzv"
    encrypt        = true
  }

  required_providers {
    archive = { source = "hashicorp/archive", version = ">= 2.4" }
    aws     = { source = "hashicorp/aws", version = ">= 5.0" }
    null    = { source = "hashicorp/null", version = ">= 3.2" }
  }

  required_version = ">= 1.5.0"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_tag
      Fleet     = var.fleet_name
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  profile_names_are_valid = alltrue([
    for server in values(var.servers) : contains(keys(var.server_profiles), server.profile)
  ])

  shared_whitelist_by_uuid = {
    for player in var.shared_whitelist : player.uuid => player
  }

  server_whitelists = {
    for server_key, server in var.servers : server_key => values(merge(
      local.shared_whitelist_by_uuid,
      { for player in server.additional_whitelist : player.uuid => player },
    ))
  }

  shared_ops_by_uuid = {
    for player in var.shared_ops : player.uuid => player
  }

  server_ops = {
    for server_key, server in var.servers : server_key => values(merge(
      local.shared_ops_by_uuid,
      { for player in server.additional_ops : player.uuid => player },
    ))
  }

  artifact_bucket_name = "${var.fleet_name}-${data.aws_caller_identity.current.account_id}-artifacts"
}

check "server_profiles_exist" {
  assert {
    condition     = local.profile_names_are_valid
    error_message = "Every server must reference a profile declared in server_profiles."
  }
}

# Retain the existing key pair state during migration. SSM is the normal
# administrative path; SSH is optional and disabled at the security group by default.
resource "null_resource" "generate_ssh_key" {
  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p "${pathexpand(var.ssh_key_pair_path)}"
      if [ ! -f "${pathexpand(var.ssh_key_pair_path)}/${var.ssh_key_pair_name}" ]; then
        ssh-keygen -t rsa -b 4096 -f "${pathexpand(var.ssh_key_pair_path)}/${var.ssh_key_pair_name}" -N ""
      fi
    EOT
  }
}

resource "aws_key_pair" "minecraft-server-key-pair" {
  key_name   = var.ssh_key_pair_name
  public_key = var.ssh_key_pair_public_key != null ? var.ssh_key_pair_public_key : file("${pathexpand(var.ssh_key_pair_path)}/${var.ssh_key_pair_name}.pub")
  depends_on = [null_resource.generate_ssh_key]

  # EC2 key-pair public material is immutable. Keep the deployed emergency key
  # during the fleet migration even if its old local .pub file is unavailable.
  lifecycle {
    ignore_changes = [public_key]
  }
}

data "aws_iam_policy_document" "minecraft_instance_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "minecraft_instance" {
  name               = "minecraft-server-instance"
  assume_role_policy = data.aws_iam_policy_document.minecraft_instance_assume_role.json
}

resource "aws_iam_role_policy_attachment" "minecraft_ssm" {
  role       = aws_iam_role.minecraft_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "minecraft" {
  name = "minecraft-server-instance"
  role = aws_iam_role.minecraft_instance.name
}

resource "aws_s3_bucket" "artifacts" {
  bucket = local.artifact_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_object" "profile_artifact" {
  for_each = {
    for name, profile in var.server_profiles : name => profile
    if profile.artifact_source_path != null
  }

  bucket = aws_s3_bucket.artifacts.id
  key    = "profiles/${each.key}/${each.value.archive_sha256}.zip"
  source = each.value.artifact_source_path
  etag   = filemd5(each.value.artifact_source_path)

  tags = {
    MinecraftProfile = each.key
    SHA256           = each.value.archive_sha256
  }

  # Multipart uploads have an ETag that is not the file MD5. The SHA-256 in
  # the profile remains the integrity control, so do not re-upload a large
  # immutable artifact just because those two ETags differ.
  lifecycle {
    ignore_changes = [etag]
  }
}

data "aws_iam_policy_document" "minecraft_artifact_read" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.artifacts.arn]
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }
}

resource "aws_iam_role_policy" "minecraft_artifact_read" {
  name   = "minecraft-fleet-artifact-read"
  role   = aws_iam_role.minecraft_instance.id
  policy = data.aws_iam_policy_document.minecraft_artifact_read.json
}

locals {
  resolved_server_profiles = {
    for name, profile in var.server_profiles : name => merge(profile, {
      archive_url = contains(keys(aws_s3_object.profile_artifact), name) ? "s3://${aws_s3_bucket.artifacts.id}/${aws_s3_object.profile_artifact[name].key}" : profile.archive_url
    })
  }
}

resource "aws_security_group" "minecraft_server_sg" {
  name = var.security_group_name
  # Preserve the deployed description so first-stage migration does not
  # replace the existing security group.
  description = "Allow Minecraft and SSH access"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = length(var.ssh_allowed_cidr_blocks) == 0 ? [] : [1]
    content {
      description = "Restricted administrative SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_allowed_cidr_blocks
    }
  }

  dynamic "ingress" {
    for_each = toset([for server in values(var.servers) : server.voice_chat_port])
    content {
      description = "Minecraft voice chat"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "udp"
      cidr_blocks = var.minecraft_allowed_cidr_blocks
    }
  }

  dynamic "ingress" {
    for_each = toset([for server in values(var.servers) : server.minecraft_port])
    content {
      description = "Minecraft"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = var.minecraft_allowed_cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

module "minecraft_server" {
  for_each = var.servers
  source   = "./modules/minecraft-server"

  server_key               = each.key
  display_name             = each.value.display_name
  profile_name             = each.value.profile
  profile                  = local.resolved_server_profiles[each.value.profile]
  instance_name            = coalesce(each.value.instance_name, "${var.fleet_name}-${each.key}")
  ami_id                   = each.value.ami_id
  instance_type            = each.value.instance_type
  subnet_id                = each.value.subnet_id
  iam_instance_profile     = aws_iam_instance_profile.minecraft.name
  security_group_ids       = [aws_security_group.minecraft_server_sg.id]
  ssh_key_pair_name        = aws_key_pair.minecraft-server-key-pair.key_name
  project_tag              = var.project_tag
  data_volume_size_gib     = each.value.data_volume_size_gib
  data_volume_kms_key_id   = each.value.data_volume_kms_key_id
  elastic_ip_enabled       = each.value.elastic_ip_enabled
  retired_data_volumes     = each.value.retired_data_volumes
  migrate_existing_data    = each.value.migrate_existing_data
  whitelist                = local.server_whitelists[each.key]
  ops                      = local.server_ops[each.key]
  java_min_memory          = each.value.java_min_memory
  java_max_memory          = each.value.java_max_memory
  server_settings          = each.value.server_settings
  simplebackups_settings   = each.value.mod_settings.simplebackups
  minecraft_port           = each.value.minecraft_port
  auto_shutdown_enabled    = each.value.auto_shutdown_enabled
  auto_shutdown_checks     = each.value.auto_shutdown_checks
  auto_shutdown_period_min = each.value.auto_shutdown_period_min
}

module "ebs_backup" {
  source      = "./modules/ebs-backup"
  project_tag = var.project_tag
  volume_ids  = { for key, server in module.minecraft_server : key => server.data_volume_id }
}

module "discord_bot_lambda" {
  source = "./modules/discord-bot-lambda"

  fleet_name           = var.fleet_name
  discord_public_key   = var.discord_public_key
  allowed_guild_id     = var.discord_allowed_guild_id
  aws_region           = var.aws_region
  project_tag          = var.project_tag
  resource_name_prefix = coalesce(var.discord_resource_name_prefix, module.minecraft_server["homestead"].instance_id)
}
