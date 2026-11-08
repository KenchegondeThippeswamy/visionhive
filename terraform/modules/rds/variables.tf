variable "name" { type = string }
variable "subnet_ids" { type = list(string) }
variable "security_group_id" { type = string }
variable "instance_class" { type = string }
variable "allocated_storage" { type = number }
variable "multi_az" { type = bool }
variable "backup_retention_days" { type = number }
variable "deletion_protection" { type = bool }
variable "skip_final_snapshot" { type = bool }

variable "engine_version" {
  type    = string
  default = "16"
}

variable "max_allocated_storage" {
  type    = number
  default = 50
}

variable "kms_key_arn" {
  type    = string
  default = null
}
