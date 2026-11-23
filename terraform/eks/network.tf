# Subnet tag that the AWS Load Balancer Controller uses to find the cluster's subnets.
resource "aws_ec2_tag" "cluster_subnet" {
  for_each    = toset(concat(local.public_subnet_ids, local.private_subnet_ids))
  resource_id = each.value
  key         = "kubernetes.io/cluster/${local.name}"
  value       = "shared"
}

# The RDS security group from Phase 5 only trusts the "app" group. Pods are not in it, so open the
# database port to the cluster's security group (which the nodes and pods use).
data "aws_security_group" "rds" {
  name   = "${local.name}-rds"
  vpc_id = local.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_eks" {
  security_group_id            = data.aws_security_group.rds.id
  referenced_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from EKS nodes and pods"
}

# Optional: the same for the EFS file system and its CSI driver.
data "aws_security_group" "efs" {
  count  = var.enable_efs_csi ? 1 : 0
  name   = "${local.name}-efs"
  vpc_id = local.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "efs_from_eks" {
  count                        = var.enable_efs_csi ? 1 : 0
  security_group_id            = data.aws_security_group.efs[0].id
  referenced_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
  description                  = "NFS from EKS nodes and pods"
}

resource "aws_eks_addon" "efs_csi" {
  count                       = var.enable_efs_csi ? 1 : 0
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-efs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  depends_on                  = [aws_eks_node_group.system]
}
