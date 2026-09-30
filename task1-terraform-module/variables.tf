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
    Master password for the RDS instance. Supply it out of band, never in a
    tfvars file that is committed:

      export TF_VAR_db_password="$(openssl rand -base64 24)"

    Task 2 replaces this with a Secrets Manager secret.
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
    Map of allow-listed sources for HTTPS on the web tier, keyed by a stable
    name such as "office-lisbon". The key becomes the Terraform address of the
    rule, so adding or removing one entry produces a plan with exactly one
    create or one destroy.
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
    error_message = "0.0.0.0/0 is not an allow-list. Name the networks that actually need access."
  }
}
