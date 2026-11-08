# One least-privilege policy per service. In the EKS phase each policy is attached to a role
# that only that service's Kubernetes service account can assume (IRSA).

data "aws_iam_policy_document" "upload_svc" {
  statement {
    sid       = "PutVideos"
    actions   = ["s3:PutObject", "s3:AbortMultipartUpload"]
    resources = ["${var.videos_bucket_arn}/uploads/*"]
  }

  statement {
    sid       = "SendJobs"
    actions   = ["sqs:SendMessage", "sqs:GetQueueAttributes"]
    resources = [var.queue_arn]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn == null ? [] : [var.kms_key_arn]
    content {
      sid       = "UseKey"
      actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
      resources = [statement.value]
    }
  }
}

data "aws_iam_policy_document" "ingest_worker" {
  statement {
    sid       = "ReadVideos"
    actions   = ["s3:GetObject"]
    resources = ["${var.videos_bucket_arn}/uploads/*"]
  }

  statement {
    sid = "ConsumeJobs"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
    ]
    resources = [var.queue_arn]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn == null ? [] : [var.kms_key_arn]
    content {
      sid       = "UseKey"
      actions   = ["kms:Decrypt"]
      resources = [statement.value]
    }
  }
}

data "aws_iam_policy_document" "eso" {
  count = var.has_db_secret ? 1 : 0

  statement {
    sid       = "ReadDatabaseSecret"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [var.db_secret_arn]
  }
}

resource "aws_iam_policy" "upload_svc" {
  name   = "${var.name}-upload-svc"
  policy = data.aws_iam_policy_document.upload_svc.json
}

resource "aws_iam_policy" "ingest_worker" {
  name   = "${var.name}-ingest-worker"
  policy = data.aws_iam_policy_document.ingest_worker.json
}

resource "aws_iam_policy" "eso" {
  count  = var.has_db_secret ? 1 : 0
  name   = "${var.name}-external-secrets"
  policy = data.aws_iam_policy_document.eso[0].json
}
