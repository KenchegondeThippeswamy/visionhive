variable "name" { type = string }
variable "visibility_timeout" { type = number }

variable "kms_key_arn" {
  type    = string
  default = null
}
