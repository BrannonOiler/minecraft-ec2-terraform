#? Get the current AWS account ID for constructing IAM resources
data "aws_caller_identity" "current" {}

#? Define the IAM policy document for EC2 management
data "aws_iam_policy_document" "lambda_ec2_policy" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:StartInstances",
      "ec2:StopInstances"
    ]
    resources = [
      "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/${var.instance_id}"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances"
    ]
    resources = ["*"]
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

#? Define the assume role policy for Lambda
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

#? Create an IAM execution role for the Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name               = "${var.instance_id}-lambda-execution-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

#? Attach the EC2 management and logging policy to the Lambda execution role
resource "aws_iam_role_policy" "lambda_ec2_policy" {
  name   = "${var.instance_id}-lambda-ec2-policy"
  role   = aws_iam_role.lambda_execution_role.id
  policy = data.aws_iam_policy_document.lambda_ec2_policy.json
}

#? Build the Lambda function code from the local "lambda" directory
resource "null_resource" "build_lambda" {
  triggers = {
    source_hash = sha256(join("", [for f in fileset("${path.module}/lambda", "**/*.ts") : filesha256("${path.module}/lambda/${f}")], [filesha256("${path.module}/lambda/package.json")], [filesha256("${path.module}/lambda/tsup.config.ts")]))
  }

  provisioner "local-exec" {
    command     = "yarn build"
    working_dir = "${path.module}/lambda"
  }
}

#? Zip the Lambda function
data "archive_file" "discord_bot_handler_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/dist"
  output_path = "${path.root}/tmp/${var.instance_id}-discord-bot-lambda.zip"

  depends_on = [null_resource.build_lambda]
}

#? Create a Lambda function to handle Discord interactions for starting/stopping the Minecraft server and checking its status
resource "aws_lambda_function" "discord_bot_handler" {
  function_name    = "${var.instance_id}-discord-bot-lambda"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  architectures    = ["arm64"]
  filename         = data.archive_file.discord_bot_handler_zip.output_path
  source_code_hash = data.archive_file.discord_bot_handler_zip.output_base64sha256
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      #! Cannot pass in AWS_REGION (reserved)
      # AWS_REGION         = var.aws_region
      INSTANCE_ID        = var.instance_id
      DISCORD_PUBLIC_KEY = var.discord_public_key
    }
  }
}

#? Expose the Lambda directly via Lambda Function URLs for simplicity (no API Gateway)
resource "aws_lambda_function_url" "discord_bot_handler_url" {
  function_name      = aws_lambda_function.discord_bot_handler.function_name
  authorization_type = "NONE" #? No auth since we'll verify requests using the Discord public key
}
