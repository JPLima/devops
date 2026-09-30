variable "name" {
  description = "Identifier prefix for the database and its subnet group."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet ids for the subnet group. At least two, in different AZs."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "RDS requires a subnet group spanning at least two availability zones."
  }
}

variable "security_group_ids" {
  description = "Security groups controlling access to the database."
  type        = list(string)
}

variable "engine" {
  description = "Database engine."
  type        = string
  default     = "postgres"
}

variable "engine_version" {
  description = "Engine version. Pin it, so a minor upgrade is a deliberate commit."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Allocated storage in GiB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Upper bound for storage autoscaling. Set equal to allocated_storage to disable."
  type        = number
  default     = 100
}

variable "database_name" {
  description = "Name of the database created on the instance."
  type        = string
  default     = "appdb"
}

variable "username" {
  description = "Master username."
  type        = string
  default     = "dbadmin"
}

variable "password" {
  description = <<-EOT
    Master password. Marked sensitive, so it is redacted from plan output, but
    it still lands in state. Task 2 shows the Secrets Manager alternative.
  EOT
  type        = string
  sensitive   = true
}

variable "port" {
  description = "Port the engine listens on."
  type        = number
  default     = 5432
}

variable "multi_az" {
  description = "Run a standby in a second availability zone."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Days of automated backups to keep. Zero disables backups."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Refuse to delete the instance through the API."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy. Never true in production."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "Customer-managed key for storage encryption. Null uses the AWS-managed RDS key."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
