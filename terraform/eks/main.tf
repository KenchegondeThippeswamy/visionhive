# EKS cluster for the dev environment. It lives in its own stack (own state file) so you can destroy the
# expensive cluster every day without touching the VPC, RDS, ECR and the rest of the dev environment.
# It reads the dev environment's outputs (VPC, subnets, IAM policies) from the dev state file in S3.
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "visionhive-tfstate-282380327737"
    key          = "visionhive/eks-dev/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "eks"
    }
  }
}

data "aws_caller_identity" "current" {}

# Outputs of the environment stack (terraform/ with env/dev.tfvars). It must be applied first.
data "terraform_remote_state" "env" {
  backend = "s3"
  config = {
    bucket = "visionhive-tfstate-282380327737"
    key    = "visionhive/${var.environment}/terraform.tfstate"
    region = var.region
  }
}

locals {
  name               = "${var.project}-${var.environment}"
  env                = data.terraform_remote_state.env.outputs
  vpc_id             = local.env.vpc_id
  public_subnet_ids  = local.env.public_subnet_ids
  private_subnet_ids = local.env.private_subnet_ids
}
