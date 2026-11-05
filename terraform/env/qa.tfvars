environment        = "qa"
vpc_cidr           = "10.20.0.0/16"
az_count           = 2
enable_nat_gateway = true
single_nat_gateway = true
ecr_tag_mutability = "IMMUTABLE"
force_destroy      = true
enable_kms         = false
