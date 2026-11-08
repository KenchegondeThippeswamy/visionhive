output "policy_arns" {
  value = {
    upload_svc       = aws_iam_policy.upload_svc.arn
    ingest_worker    = aws_iam_policy.ingest_worker.arn
    external_secrets = try(aws_iam_policy.eso[0].arn, null)
  }
}
