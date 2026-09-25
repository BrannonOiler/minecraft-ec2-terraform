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
