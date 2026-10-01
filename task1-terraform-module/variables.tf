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

variable "db_password" {
  description = <<-EOT
    RDS master password. Supply out of band, never in a committed tfvars:
    export TF_VAR_db_password="$(openssl rand -base64 24)"
  EOT
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 16
    error_message = "db_password must be at least 16 characters."
  }
}

variable "web_ingress_cidrs" {
  description = <<-EOT
    Allow-listed sources for HTTPS on the web tier, keyed by network name.
    The key becomes the Terraform address of the generated rule.
  EOT
  type        = map(string)

  default = {
    "office-lisbon" = "203.0.113.10/32"
  }

  validation {
    condition     = alltrue([for cidr in values(var.web_ingress_cidrs) : can(cidrhost(cidr, 0))])
    error_message = "Every value must be a valid IPv4 CIDR."
  }

  validation {
    condition     = !contains(values(var.web_ingress_cidrs), "0.0.0.0/0")
    error_message = "0.0.0.0/0 is not an allow-list. Name the networks that need access."
  }
}
