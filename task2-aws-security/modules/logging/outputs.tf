output "trail_arn" {
  description = "ARN of the CloudTrail trail."
  value       = aws_cloudtrail.this.arn
}

output "trail_name" {
  description = "Name of the trail."
  value       = aws_cloudtrail.this.name
}

output "bucket_name" {
  description = "Bucket receiving trail objects."
  value       = aws_s3_bucket.trail.id
}

output "bucket_arn" {
  description = "ARN of the trail bucket."
  value       = aws_s3_bucket.trail.arn
}

output "log_group_name" {
  description = "CloudWatch log group the trail writes to. Metric filters attach here."
  value       = aws_cloudwatch_log_group.trail.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group."
  value       = aws_cloudwatch_log_group.trail.arn
}
