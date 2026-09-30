output "arn" {
  description = "Key ARN, which is what most resources expect."
  value       = aws_kms_key.this.arn
}

output "key_id" {
  description = "Key id."
  value       = aws_kms_key.this.key_id
}

output "alias" {
  description = "Full alias, including the alias/ prefix."
  value       = aws_kms_alias.this.name
}
