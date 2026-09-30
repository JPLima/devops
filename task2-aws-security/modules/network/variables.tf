variable "name" {
  description = "Name prefix for every resource."
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.30.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across."
  type        = number
  default     = 2
}

variable "flow_logs_kms_key_arn" {
  description = "KMS key encrypting the flow log group."
  type        = string
}

variable "flow_logs_retention_days" {
  description = <<-EOT
    Retention for the VPC flow log group. One year by default, which is the
    floor most compliance regimes expect. Flow logs are voluminous, so this is
    the first dial to turn if the CloudWatch bill matters more than the
    lookback window.
  EOT
  type        = number
  default     = 365
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
