output "vpc_id" {
  description = "VPC id."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet ids. The instance runs here."
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet ids. They hold the NAT gateways."
  value       = module.vpc.public_subnet_ids
}

output "instance_id" {
  description = "Instance id. Connect with: aws ssm start-session --target <id>"
  value       = module.compute.instance_id
}

output "instance_private_ip" {
  description = "Private IP of the instance."
  value       = module.compute.private_ip
}

output "instance_security_group_id" {
  description = "Security group attached to the instance."
  value       = module.app_sg.id
}

output "instance_role_arn" {
  description = "ARN of the least-privilege instance role."
  value       = module.iam.role_arn
}

output "data_bucket_name" {
  description = "Application data bucket."
  value       = aws_s3_bucket.data.id
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail."
  value       = module.logging.trail_arn
}

output "cloudtrail_bucket_name" {
  description = "Bucket receiving trail objects."
  value       = module.logging.bucket_name
}

output "cloudtrail_log_group_name" {
  description = "CloudWatch log group the trail writes to."
  value       = module.logging.log_group_name
}

output "config_recorder_name" {
  description = "AWS Config recorder name."
  value       = module.config.recorder_name
}

output "config_rule_names" {
  description = "Config rules deployed, keyed by short name."
  value       = module.config.rule_names
}

output "security_alarm_names" {
  description = "CloudWatch alarms watching the trail, keyed by detection name."
  value       = module.alerting.alarm_names
}

output "security_topic_arn" {
  description = "SNS topic the alarms publish to."
  value       = module.alerting.topic_arn
}

output "flow_log_group_name" {
  description = "CloudWatch log group receiving VPC flow logs."
  value       = module.vpc.flow_log_group_name
}

output "application_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the database credential."
  value       = module.app_secret.secret_arn
}

output "kms_key_arns" {
  description = "The three customer-managed keys, by purpose."
  value = {
    observability = module.observability_key.arn
    data          = module.data_key.arn
    secrets       = module.secrets_key.arn
  }
}
