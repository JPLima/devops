variable "project" {
  description = "Project name, used as a prefix for every resource name."
  type        = string
  default     = "betontalent"
}

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.30.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across."
  type        = number
  default     = 2
}

variable "instance_type" {
  description = "Instance type for the private application host."
  type        = string
  default     = "t3.micro"
}

variable "security_notification_emails" {
  description = <<-EOT
    Addresses that receive security alarms. Each subscription stays pending
    until the recipient confirms by email; Terraform cannot confirm for them.
  EOT
  type        = list(string)
  default     = []
}

variable "flow_logs_retention_days" {
  description = "Retention for the VPC flow log group."
  type        = number
  default     = 365
}

variable "cloudtrail_retention_days" {
  description = "Retention for the CloudTrail CloudWatch log group."
  type        = number
  default     = 365
}
