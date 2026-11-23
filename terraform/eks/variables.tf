variable "project" {
  type    = string
  default = "visionhive"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "region" {
  type    = string
  default = "ap-southeast-2"
}

variable "kubernetes_version" {
  type        = string
  default     = null
  description = "null = the version EKS currently offers by default. Check that it is in standard support: older versions cost much more (extended support)."
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t8i.small"]
}

variable "node_desired_size" {
  type    = number
  default = 1
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 1
}

variable "private_nodes" {
  type        = bool
  default     = false
  description = "false = nodes in public subnets (no NAT gateway needed, cheaper, fine for a learning environment). true = private subnets, which needs enable_nat_gateway = true in the dev environment."
}

variable "api_allowed_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Who can reach the Kubernetes API endpoint (IAM still protects it). Use your own address as x.x.x.x/32 to harden it."
}

variable "enable_efs_csi" {
  type        = bool
  default     = false
  description = "Install the EFS CSI driver add-on and open the EFS security group to the cluster (to mount the Phase 5 file system)."
}

variable "admin_principal_arns" {
  type        = list(string)
  default     = []
  description = "Extra IAM users or roles that get cluster admin. The identity that creates the cluster is admin already."
}

variable "app_namespace" {
  type    = string
  default = "visionhive"
}
