variable "name" {
  description = "Name prefix for the role, policy and instance profile."
  type        = string
}

variable "data_bucket_arn" {
  description = "ARN of the one S3 bucket this instance may read and write."
  type        = string
}

variable "data_bucket_prefix" {
  description = <<-EOT
    Key prefix inside the bucket the instance may touch. The default of "*"
    means the whole bucket; narrow it when the workload only owns part of one.
  EOT
  type        = string
  default     = "*"
}

variable "kms_key_arn" {
  description = "ARN of the key encrypting the bucket. Without kms: permissions, s3: permissions alone fail on an encrypted object."
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
