output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "videos_bucket" {
  value = module.videos_bucket.bucket_name
}

output "jobs_queue_url" {
  value = module.jobs_queue.queue_url
}

output "jobs_dlq_url" {
  value = module.jobs_queue.dlq_url
}

output "kms_key_arn" {
  value = local.kms_key_arn
}
