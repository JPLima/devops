variable "name" {
  description = "Name prefix for the trail and its bucket."
  type        = string
}

variable "bucket_name" {
  description = "Globally unique name for the CloudTrail bucket."
  type        = string
}

variable "kms_key_arn" {
  description = "Key encrypting the trail's objects and its CloudWatch log group."
  type        = string
}

variable "log_retention_days" {
  description = "Retention for the CloudWatch log group the trail writes to."
  type        = number
  default     = 365
}

variable "s3_expiration_days" {
  description = "Days before trail objects in S3 expire. Zero keeps them forever."
  type        = number
  default     = 730
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
