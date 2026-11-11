output "role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "allowed_subjects" {
  value = local.subjects
}
