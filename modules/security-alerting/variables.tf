variable "name" {
  description = "Name prefix for the topic, filters and alarms."
  type        = string
}

variable "log_group_name" {
  description = "CloudTrail CloudWatch log group the metric filters read."
  type        = string
}

variable "kms_key_arn" {
  description = "Key encrypting the SNS topic."
  type        = string
}

variable "notification_emails" {
  description = <<-EOT
    Addresses subscribed to the alarm topic. Each subscription starts as
    pending until the recipient confirms; Terraform cannot confirm for them.
  EOT
  type        = list(string)
  default     = []
}

variable "metric_namespace" {
  description = "CloudWatch namespace for the metrics these filters publish."
  type        = string
  default     = "Security"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
