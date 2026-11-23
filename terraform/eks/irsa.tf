# IAM permissions for the AWS Load Balancer Controller.
resource "aws_iam_policy" "alb_controller" {
  name   = "${local.name}-alb-controller"
  policy = file("${path.module}/policies/alb_iam_policy.json")
}


locals {
  eso_policy_arn = try(local.env.service_policy_arns.external_secrets, "")

  pod_identity_all = {
    "ebs-csi" = {
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
      policy_arns     = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
    }

    "aws-load-balancer-controller" = {
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
      policy_arns     = [aws_iam_policy.alb_controller.arn]
    }

    "external-secrets" = {
      namespace       = "external-secrets"
      service_account = "external-secrets"
      policy_arns     = [local.eso_policy_arn]
    }

    "upload-svc" = {
      namespace       = var.app_namespace
      service_account = "upload-svc"
      policy_arns     = [local.env.service_policy_arns.upload_svc]
    }

    "ingest-worker" = {
      namespace       = var.app_namespace
      service_account = "ingest-worker"
      policy_arns     = [local.env.service_policy_arns.ingest_worker]
    }
  }

  pod_identity_roles = {
    for k, v in local.pod_identity_all :
    k => v
    if k != "external-secrets" || local.eso_policy_arn != ""
  }

  pod_identity_attachments = merge([
    for role_name, role in local.pod_identity_roles : {
      for index, policy_arn in role.policy_arns :
      "${role_name}-${index}" => {
        role       = role_name
        policy_arn = policy_arn
      }
      if policy_arn != ""
    }
  ]...)
}

# Pod Identity trust policy: no OIDC provider is required.
data "aws_iam_policy_document" "pod_identity_trust" {
  for_each = local.pod_identity_roles

  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_eks_cluster.this.arn]
    }
  }
}

resource "aws_iam_role" "pod_identity" {
  for_each = local.pod_identity_roles

  name               = "${local.name}-pod-identity-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust[each.key].json
}

resource "aws_iam_role_policy_attachment" "pod_identity" {
  for_each = local.pod_identity_attachments

  role       = aws_iam_role.pod_identity[each.value.role].name
  policy_arn = each.value.policy_arn
}

# Associations for application and controller service accounts.
# EBS CSI is associated directly through its managed add-on configuration.
resource "aws_eks_pod_identity_association" "services" {
  for_each = {
    for k, v in local.pod_identity_roles :
    k => v
    if k != "ebs-csi"
  }

  cluster_name    = aws_eks_cluster.this.name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.pod_identity[each.key].arn

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.pod_identity
  ]
}
