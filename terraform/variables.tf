variable "project" {
  type    = string
  default = "visionhive"
}

variable "environment" {
  type        = string
  description = "dev, qa or prod"
  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment must be dev, qa or prod."
  }
}

variable "region" {
  type    = string
  default = "ap-southeast-2" # change if you use another region
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR of the VPC, must be a /16"
}

variable "az_count" {
  type    = number
  default = 2
}

variable "enable_nat_gateway" {
  type        = bool
  default     = false
  description = "NAT gateways cost money per hour. Keep false until you need private subnets to reach the internet."
}

variable "single_nat_gateway" {
  type        = bool
  default     = true
  description = "true = one shared NAT (cheaper), false = one per AZ (more resilient)"
}

variable "ecr_repositories" {
  type    = list(string)
  default = ["api-gateway", "upload-svc", "ingest-worker"]
}

variable "ecr_tag_mutability" {
  type    = string
  default = "MUTABLE"
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "true lets terraform destroy delete non-empty buckets and repos (dev only)"
}

variable "enable_kms" {
  type    = bool
  default = false
}

variable "queue_visibility_timeout" {
  type    = number
  default = 60
}
