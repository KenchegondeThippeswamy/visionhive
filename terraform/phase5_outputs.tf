output "rds_endpoint" {
  value = var.enable_rds ? module.rds[0].endpoint : null
}

output "rds_secret_arn" {
  value = var.enable_rds ? module.rds[0].master_user_secret_arn : null
}

output "efs_id" {
  value = var.enable_efs ? module.efs[0].file_system_id : null
}

output "efs_access_point_id" {
  value = var.enable_efs ? module.efs[0].access_point_id : null
}

output "service_policy_arns" {
  value = module.iam_policies.policy_arns
}

output "bastion_instance_id" {
  value = var.enable_bastion ? module.bastion[0].instance_id : null
}

output "app_security_group_id" {
  value = module.security.app_sg_id
}
