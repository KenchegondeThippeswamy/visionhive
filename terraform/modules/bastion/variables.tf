variable "name" { type = string }
variable "subnet_id" { type = string }
variable "security_group_id" { type = string }

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "has_db_secret" {
  type        = bool
  default     = false
  description = "Known at plan time. Decides whether the bastion may read the database secret."
}

variable "db_secret_arn" {
  type    = string
  default = null
}
