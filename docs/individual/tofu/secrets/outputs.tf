output "secret_arn" {
  value = aws_secretsmanager_secret.db.arn
}

output "secret_name" {
  value = aws_secretsmanager_secret.db.name
}

output "policy_arn" {
  value = aws_iam_policy.app_secret.arn
}

output "app_role_name" {
  value = data.aws_iam_role.app.name
}
