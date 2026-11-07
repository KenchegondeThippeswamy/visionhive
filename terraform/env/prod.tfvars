environment        = "prod"
vpc_cidr           = "10.30.0.0/16"
az_count           = 3
enable_nat_gateway = true
single_nat_gateway = false
ecr_tag_mutability = "IMMUTABLE"
force_destroy      = false
enable_kms         = true
