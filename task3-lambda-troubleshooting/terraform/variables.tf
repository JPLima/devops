variable "bucket_prefix" {
  description = <<-EOT
    Prefix for the data bucket. A random suffix is appended, because S3 bucket
    names are a single global namespace and the original hardcoded name was
    almost certainly already taken by someone else attempting this challenge.
  EOT
  type        = string
  default     = "my-super-cool-bucket"
}

variable "function_name" {
  description = "Name of the Lambda function."
  type        = string
  default     = "my_lambda"
}

variable "runtime" {
  description = <<-EOT
    Python runtime. The original specified python3.8, which reached end of
    support in October 2024; AWS refuses to create new functions on it.
  EOT
  type        = string
  default     = "python3.12"
}

variable "log_retention_days" {
  description = <<-EOT
    Retention for the function's CloudWatch log group. One year, which is the
    floor most compliance regimes expect. Turn it down if the CloudWatch bill
    matters more than the lookback window.
  EOT
  type        = number
  default     = 365
}

variable "reserved_concurrent_executions" {
  description = <<-EOT
    Maximum concurrent executions. Caps the blast radius: a runaway trigger
    cannot consume the account's entire concurrency pool and starve every other
    function. -1 means unreserved.
  EOT
  type        = number
  default     = 10
}

variable "timeout" {
  description = "Function timeout in seconds. The default of 3 is tight for two S3 round trips on a cold start."
  type        = number
  default     = 30
}

variable "memory_size" {
  description = "Memory in MB. CPU scales with memory, so this also sets how fast the runtime initialises."
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
