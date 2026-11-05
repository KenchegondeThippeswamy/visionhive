provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  name                 = "${var.project}-${var.environment}"
  azs                  = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  public_subnet_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnet_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 10)]
  kms_key_arn          = var.enable_kms ? module.kms[0].key_arn : null
}

module "kms" {
  count  = var.enable_kms ? 1 : 0
  source = "./modules/kms"
  name   = local.name
}

module "vpc" {
  source               = "./modules/vpc"
  name                 = local.name
  region               = var.region
  cidr                 = var.vpc_cidr
  azs                  = local.azs
  public_subnet_cidrs  = local.public_subnet_cidrs
  private_subnet_cidrs = local.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway
}

module "ecr" {
  source         = "./modules/ecr"
  prefix         = local.name
  repositories   = var.ecr_repositories
  tag_mutability = var.ecr_tag_mutability
  force_delete   = var.force_destroy
  kms_key_arn    = local.kms_key_arn
}

module "videos_bucket" {
  source        = "./modules/s3"
  bucket_name   = "${local.name}-videos-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.force_destroy
  kms_key_arn   = local.kms_key_arn
}

module "jobs_queue" {
  source             = "./modules/sqs"
  name               = "${local.name}-jobs"
  visibility_timeout = var.queue_visibility_timeout
  kms_key_arn        = local.kms_key_arn
}
