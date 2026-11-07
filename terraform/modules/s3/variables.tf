variable "bucket_name" { type = string }
variable "force_destroy" { type = bool }

variable "kms_key_arn" {
  type    = string
  default = null
}
