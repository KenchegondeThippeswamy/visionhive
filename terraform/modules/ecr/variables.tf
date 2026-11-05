variable "prefix" { type = string }
variable "repositories" { type = list(string) }
variable "tag_mutability" { type = string }
variable "force_delete" { type = bool }

variable "kms_key_arn" {
  type    = string
  default = null
}
