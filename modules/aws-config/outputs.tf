output "recorder_name" {
  description = "Name of the configuration recorder."
  value       = aws_config_configuration_recorder.this.name
}

output "bucket_name" {
  description = "Bucket AWS Config delivers snapshots to."
  value       = aws_s3_bucket.config.id
}

output "role_arn" {
  description = "ARN of the role AWS Config assumes."
  value       = aws_iam_role.config.arn
}

output "rule_names" {
  description = "Map of short rule name to the deployed Config rule name."
  value       = { for key, rule in aws_config_config_rule.managed : key => rule.name }
}
