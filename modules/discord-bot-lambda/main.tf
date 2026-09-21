data "aws_caller_identity" "current" {}

locals {
  interaction_table_name = "${var.fleet_name}-discord-interactions"
}

resource "aws_dynamodb_table" "interactions" {
  name         = local.interaction_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "interaction_id"

  attribute {
    name = "interaction_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  server_side_encryption { enabled = true }
}

data "aws_iam_policy_document" "lambda_ec2_policy" {
  statement {
    effect    = "Allow"
    actions   = ["ec2:StartInstances"]
    resources = ["arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/Project"
      values   = [var.project_tag]
    }
    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/DiscordManaged"
      values   = ["true"]
    }
  }

  statement {
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript"]
  }

  statement {
    effect    = "Allow"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/Project"
      values   = [var.project_tag]
    }
    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/DiscordManaged"
      values   = ["true"]
    }
  }

  statement {
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.interactions.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"]
  }
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name               = "${var.resource_name_prefix}-lambda-execution-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_iam_role_policy" "lambda_ec2_policy" {
  name   = "${var.resource_name_prefix}-lambda-ec2-policy"
  role   = aws_iam_role.lambda_execution_role.id
  policy = data.aws_iam_policy_document.lambda_ec2_policy.json
}

resource "null_resource" "build_lambda" {
  triggers = {
    source_hash = sha256(join("", concat(
      [for f in fileset("${path.module}/lambda", "**/*.ts") : filesha256("${path.module}/lambda/${f}")],
      [filesha256("${path.module}/lambda/package.json")],
      [filesha256("${path.module}/lambda/yarn.lock")],
      [filesha256("${path.module}/lambda/tsup.config.ts")]
    )))
  }

  provisioner "local-exec" {
    command     = "yarn install --frozen-lockfile && yarn tsup"
    working_dir = "${path.module}/lambda"
  }
}

data "archive_file" "discord_bot_handler_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/dist"
  output_path = "${path.root}/tmp/${var.resource_name_prefix}-discord-bot-lambda.zip"

  depends_on = [null_resource.build_lambda]
}

resource "aws_lambda_function" "discord_bot_handler" {
  function_name                  = "${var.resource_name_prefix}-discord-bot-lambda"
  role                           = aws_iam_role.lambda_execution_role.arn
  handler                        = "index.handler"
  runtime                        = "nodejs22.x"
  architectures                  = ["arm64"]
  filename                       = data.archive_file.discord_bot_handler_zip.output_path
  source_code_hash               = data.archive_file.discord_bot_handler_zip.output_base64sha256
  timeout                        = 10
  memory_size                    = 256
  reserved_concurrent_executions = 10

  environment {
    variables = {
      ALLOWED_GUILD_ID          = var.allowed_guild_id
      DISCORD_INTERACTION_TABLE = aws_dynamodb_table.interactions.name
      DISCORD_PUBLIC_KEY        = var.discord_public_key
      SERVER_PROJECT_TAG_VALUE  = var.project_tag
    }
  }
}

resource "aws_lambda_function_url" "discord_bot_handler_url" {
  function_name      = aws_lambda_function.discord_bot_handler.function_name
  authorization_type = "NONE"
}
