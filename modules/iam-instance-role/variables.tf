variable "name" {
  description = "Name prefix for the role, policy and instance profile."
  type        = string
}

variable "data_bucket_arn" {
  description = "ARN of the one S3 bucket this instance may read and write."
  type        = string
}

variable "data_bucket_prefix" {
  description = "Key prefix inside the bucket the instance may touch."
  type        = string
  default     = "*"
}

variable "kms_key_arn" {
  description = "Key encrypting the bucket. s3 permissions alone fail on an encrypted object."
  type        = string
}

variable "secret_arns" {
  description = "Secrets Manager secrets this instance may read. Empty means none."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to the role."
  type        = map(string)
  default     = {}
}
