output "topic_arn" {
  description = "SNS topic the alarms publish to."
  value       = aws_sns_topic.security.arn
}

output "alarm_names" {
  description = "Map of detection name to CloudWatch alarm name."
  value       = { for key, alarm in aws_cloudwatch_metric_alarm.this : key => alarm.alarm_name }
}

output "metric_filter_names" {
  description = "Map of detection name to metric filter name."
  value       = { for key, filter in aws_cloudwatch_log_metric_filter.this : key => filter.name }
}
