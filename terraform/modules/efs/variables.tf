variable "name" { type = string }
variable "subnet_ids" { type = list(string) }
variable "security_group_id" { type = string }
variable "backup_enabled" { type = bool }

variable "kms_key_arn" {
  type    = string
  default = null
}
