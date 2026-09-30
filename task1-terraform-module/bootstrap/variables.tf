variable "project" {
  description = "Project name, used to build resource names."
  type        = string
  default     = "betontalent"
}

variable "region" {
  description = "AWS region for the backend resources."
  type        = string
  default     = "eu-west-1"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket holding Terraform state. Must be globally unique."
  type        = string
}

variable "lock_table_name" {
  description = "Name of the DynamoDB table used for state locking."
  type        = string
  default     = "betontalent-terraform-locks"
}
