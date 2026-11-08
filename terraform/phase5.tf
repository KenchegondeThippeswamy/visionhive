module "security" {
  source = "./modules/security"
  name   = local.name
  vpc_id = module.vpc.vpc_id
}

module "rds" {
  count                 = var.enable_rds ? 1 : 0
  source                = "./modules/rds"
  name                  = local.name
  subnet_ids            = module.vpc.private_subnet_ids
  security_group_id     = module.security.rds_sg_id
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  multi_az              = var.db_multi_az
  backup_retention_days = var.db_backup_retention_days
  deletion_protection   = var.db_deletion_protection
  skip_final_snapshot   = var.db_skip_final_snapshot
  kms_key_arn           = local.kms_key_arn
}

module "efs" {
  count             = var.enable_efs ? 1 : 0
  source            = "./modules/efs"
  name              = local.name
  subnet_ids        = module.vpc.private_subnet_ids
  security_group_id = module.security.efs_sg_id
  backup_enabled    = var.efs_backup_enabled
  kms_key_arn       = local.kms_key_arn
}

module "iam_policies" {
  source            = "./modules/iam-policies"
  name              = local.name
  videos_bucket_arn = module.videos_bucket.bucket_arn
  queue_arn         = module.jobs_queue.queue_arn
  db_secret_arn     = var.enable_rds ? module.rds[0].master_user_secret_arn : null
  kms_key_arn       = local.kms_key_arn
}

module "bastion" {
  count             = var.enable_bastion ? 1 : 0
  source            = "./modules/bastion"
  name              = local.name
  subnet_id         = module.vpc.public_subnet_ids[0]
  security_group_id = module.security.app_sg_id
  db_secret_arn     = var.enable_rds ? module.rds[0].master_user_secret_arn : null
}
