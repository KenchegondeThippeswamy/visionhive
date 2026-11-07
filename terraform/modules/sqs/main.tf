resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-dlq"
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = var.kms_key_arn == null ? true : null
  kms_master_key_id         = var.kms_key_arn
}

resource "aws_sqs_queue" "main" {
  name                       = var.name
  visibility_timeout_seconds = var.visibility_timeout
  sqs_managed_sse_enabled    = var.kms_key_arn == null ? true : null
  kms_master_key_id          = var.kms_key_arn

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}
