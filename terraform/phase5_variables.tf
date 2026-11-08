variable "enable_rds" {
  type        = bool
  default     = false
  description = "Create the PostgreSQL database. Set false to remove only the database and save money."
}

variable "enable_efs" {
  type    = bool
  default = false
}

variable "enable_bastion" {
  type        = bool
  default     = false
  description = "Small test instance (SSM access, no SSH) inside the VPC to reach RDS and EFS"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "db_backup_retention_days" {
  type    = number
  default = 1
}

variable "db_deletion_protection" {
  type    = bool
  default = false
}

variable "db_skip_final_snapshot" {
  type    = bool
  default = true
}

variable "efs_backup_enabled" {
  type    = bool
  default = false
}
