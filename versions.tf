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
