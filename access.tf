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
