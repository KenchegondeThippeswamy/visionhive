variable "name" { type = string }
variable "videos_bucket_arn" { type = string }
variable "queue_arn" { type = string }

variable "has_db_secret" {
  type        = bool
  default     = false
  description = "Known at plan time. Decides whether the External Secrets policy is created."
}

variable "db_secret_arn" {
  type    = string
  default = null
}

variable "kms_key_arn" {
  type    = string
  default = null
}
