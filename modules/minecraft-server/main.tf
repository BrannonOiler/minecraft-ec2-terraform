data "aws_subnet" "selected" {
  id = var.subnet_id
}

locals {
  common_tags = {
    Name             = var.instance_name
    Project          = var.project_tag
    MinecraftServer  = var.server_key
    MinecraftName    = var.display_name
    MinecraftPort    = tostring(var.minecraft_port)
    MinecraftProfile = var.profile_name
    DiscordManaged   = "true"
  }

  config_env = templatefile("${path.module}/server-config.env.tftpl", {
    profile_name             = var.profile_name
    archive_url              = var.profile.archive_url
    archive_sha256           = var.profile.archive_sha256
    archive_directory        = var.profile.archive_directory
    java_major               = var.profile.java_major
    start_command            = var.profile.start_command
    layout                   = var.profile.layout
    forge_installer_jar      = var.profile.forge_installer_jar
    java_min_memory          = var.java_min_memory
    java_max_memory          = var.java_max_memory
    server_settings          = var.server_settings
    simplebackups_settings   = var.simplebackups_settings
    minecraft_port           = var.minecraft_port
    auto_shutdown_enabled    = var.auto_shutdown_enabled
    auto_shutdown_checks     = var.auto_shutdown_checks
    auto_shutdown_period_min = var.auto_shutdown_period_min
  })
}

resource "aws_ebs_volume" "data" {
  availability_zone = data.aws_subnet.selected.availability_zone
  size              = var.data_volume_size_gib
  type              = "gp3"
  encrypted         = true
  kms_key_id        = var.data_volume_kms_key_id

  tags = merge(local.common_tags, {
    Name   = "${var.instance_name}-data"
    Backup = "minecraft"
  })

  lifecycle {
    prevent_destroy = true
  }
}

# Retained after a controlled shrink migration. These volumes are deliberately
# excluded from DLM protection and cannot be deleted by a routine apply.
data "aws_ebs_volume" "retired" {
  for_each = var.retired_data_volumes

  filter {
    name   = "volume-id"
    values = [each.value.volume_id]
  }
}

resource "aws_ebs_volume" "retired_data" {
  for_each          = var.retired_data_volumes
  availability_zone = data.aws_ebs_volume.retired[each.key].availability_zone
  size              = data.aws_ebs_volume.retired[each.key].size
  type              = data.aws_ebs_volume.retired[each.key].volume_type
  encrypted         = data.aws_ebs_volume.retired[each.key].encrypted
  kms_key_id        = data.aws_ebs_volume.retired[each.key].kms_key_id

  tags = merge(local.common_tags, {
    Name            = each.value.name
    RetiredData     = "true"
    MigrationSource = "data-volume-shrink"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_instance" "this" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.ssh_key_pair_name
  subnet_id              = var.subnet_id
  iam_instance_profile   = var.iam_instance_profile
  vpc_security_group_ids = var.security_group_ids

  # The root volume remains disposable. The separately managed data volume has
  # its own tags; instance-level volume_tags would otherwise overwrite them.
  tags = local.common_tags

  lifecycle {
    ignore_changes = [volume_tags]
  }
}

# Root disks are disposable, but still carry a clear server identity for
# inventory and the short retention period before data migration completes.
resource "aws_ec2_tag" "root_volume" {
  for_each = merge(local.common_tags, { Name = "${var.instance_name}-root" })

  resource_id = aws_instance.this.root_block_device[0].volume_id
  key         = each.key
  value       = each.value
}

# The primary ENI is created with the instance and is server-specific. Tag it
# explicitly so the AWS console and inventory exports do not leave it unnamed.
resource "aws_ec2_tag" "primary_network_interface" {
  for_each = merge(local.common_tags, { Name = "${var.instance_name}-network" })

  resource_id = aws_instance.this.primary_network_interface_id
  key         = each.key
  value       = each.value
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.this.id
}

resource "aws_ssm_association" "configure_server" {
  name             = "AWS-RunShellScript"
  association_name = var.server_key == "homestead" ? null : "${var.instance_name}-configure"

  tags = var.server_key == "homestead" ? {} : merge(local.common_tags, {
    Name = "${var.instance_name}-configure"
  })

  targets {
    key    = "InstanceIds"
    values = [aws_instance.this.id]
  }

  parameters = {
    commands = <<-EOT
      set -euo pipefail
      install -d -m 0755 /opt/minecraft-fleet
      echo '${base64encode(file("${path.root}/scripts/configure-server.sh"))}' | base64 --decode >/opt/minecraft-fleet/configure-server.sh
      echo '${base64encode(file("${path.root}/scripts/ec2-setup.sh"))}' | base64 --decode >/opt/minecraft-fleet/ec2-setup.sh
      echo '${base64encode(file("${path.root}/scripts/auto-shutdown.sh"))}' | base64 --decode >/opt/minecraft-fleet/auto-shutdown.sh
      echo '${base64encode(local.config_env)}' | base64 --decode >/opt/minecraft-fleet/server-config.env
      echo '${base64encode(templatefile("${path.root}/templates/whitelist.tpl", { whitelist = var.whitelist }))}' | base64 --decode >/opt/minecraft-fleet/whitelist.json
      echo '${base64encode(templatefile("${path.root}/templates/ops.tpl", { ops = var.ops }))}' | base64 --decode >/opt/minecraft-fleet/ops.json
      chmod 700 /opt/minecraft-fleet/configure-server.sh /opt/minecraft-fleet/ec2-setup.sh /opt/minecraft-fleet/auto-shutdown.sh
      DATA_VOLUME_ID='${aws_ebs_volume.data.id}' MIGRATE_EXISTING_DATA='${var.migrate_existing_data}' /opt/minecraft-fleet/configure-server.sh
    EOT
  }

  schedule_expression         = "rate(30 minutes)"
  apply_only_at_cron_interval = false
  compliance_severity         = "HIGH"
  max_concurrency             = "1"
  max_errors                  = "0"

  depends_on = [aws_volume_attachment.data]
}

resource "aws_eip" "this" {
  for_each = var.elastic_ip_enabled ? { active = true } : {}
  domain   = "vpc"
  instance = aws_instance.this.id

  tags = merge(local.common_tags, {
    Name = "${var.instance_name}-eip"
  })
}

# Preserve an opted-in existing Elastic IP while transitioning the module to
# dynamic public addresses. Servers without the opt-in simply release theirs.
moved {
  from = aws_eip.this
  to   = aws_eip.this["active"]
}
