variable "region" {
  type    = string
  default = "ap-southeast-2"
}

variable "github_owner" {
  type    = string
  default = "KenchegondeThippeswamy"
}

variable "github_repo" {
  type    = string
  default = "visionhive"
}

variable "branches" {
  type        = list(string)
  default     = ["dev"]
  description = "Branches whose workflow runs may push images. Pull requests are never allowed."
}

variable "ecr_prefix" {
  type        = string
  default     = "visionhive-dev"
  description = "The role may push only to repositories named <prefix>/*"
}

variable "role_name" {
  type    = string
  default = "visionhive-github-actions-ecr"
}

variable "create_oidc_provider" {
  type        = bool
  default     = true
  description = "An AWS account can have only one GitHub OIDC provider. Set false if it already exists."
}
