variable "bucket_prefix" {
  description = "Prefix for the data bucket. A random suffix is appended."
  type        = string
  default     = "my-super-cool-bucket"
}

variable "function_name" {
  description = "Name of the Lambda function."
  type        = string
  default     = "my_lambda"
}

variable "runtime" {
  description = "Python runtime. The original was python3.8, past end of support."
  type        = string
  default     = "python3.12"
}

variable "log_retention_days" {
  description = "Retention for the function log group."
  type        = number
  default     = 365
}

variable "reserved_concurrent_executions" {
  description = "Maximum concurrent executions. -1 means unreserved."
  type        = number
  default     = 10
}

variable "timeout" {
  description = "Function timeout in seconds."
  type        = number
  default     = 30
}

variable "memory_size" {
  description = "Memory in MB. CPU scales with it."
  type        = number
  default     = 256
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)

  default = {
    Project   = "betontalent"
    Task      = "task3"
    ManagedBy = "terraform"
  }
}
