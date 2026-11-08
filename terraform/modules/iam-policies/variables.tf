variable "name" { type = string }
variable "videos_bucket_arn" { type = string }
variable "queue_arn" { type = string }

variable "db_secret_arn" {
  type    = string
  default = null
}

variable "kms_key_arn" {
  type    = string
  default = null
}
