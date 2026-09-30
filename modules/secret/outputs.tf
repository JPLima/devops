output "secret_arn" {
  description = "ARN of the secret, for granting read access in an IAM policy."
  value       = aws_secretsmanager_secret.this.arn
}

output "secret_name" {
  description = "Name of the secret."
  value       = aws_secretsmanager_secret.this.name
}

output "username" {
  description = "Username stored in the secret. The password is not exposed as an output."
  value       = var.username
}
