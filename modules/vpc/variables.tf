variable "name" {
  description = "Name prefix for every resource in the VPC."
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC."
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR, for example 10.0.0.0/16."
  }
}

variable "az_count" {
  description = "Availability zones to spread subnets across."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "az_count must be between 2 and 4. Two is the minimum for an RDS subnet group."
  }
}

variable "subnet_newbits" {
  description = "Bits added to the VPC prefix to size each subnet. With a /16, 8 gives /24s."
  type        = number
  default     = 8
}

variable "map_public_ip_on_launch" {
  description = "Whether public subnets hand out public IPs. Set true for an internet-facing tier."
  type        = bool
  default     = false
}

variable "enable_nat_gateway" {
  description = "Create NAT gateways so private subnets reach the internet."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "One shared NAT instead of one per AZ. Cheaper, but a single point of failure."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Flow logs
# ---------------------------------------------------------------------------

variable "enable_flow_logs" {
  description = "Record VPC Flow Logs to CloudWatch Logs."
  type        = bool
  default     = false
}

variable "flow_logs_kms_key_arn" {
  description = "KMS key encrypting the flow log group. Required when enable_flow_logs is true."
  type        = string
  default     = null

  # Checked in a precondition on the log group rather than here, because a
  # variable validation cannot see another variable.
}

variable "flow_logs_retention_days" {
  description = "Retention for the flow log group."
  type        = number
  default     = 365
}

variable "flow_logs_traffic_type" {
  description = "ACCEPT, REJECT or ALL."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_logs_traffic_type)
    error_message = "flow_logs_traffic_type must be ACCEPT, REJECT or ALL."
  }
}

# ---------------------------------------------------------------------------
# VPC endpoints
# ---------------------------------------------------------------------------

variable "interface_endpoints" {
  description = <<-EOT
    Interface endpoint service names without the com.amazonaws.<region>.
    prefix. Session Manager needs ["ssm", "ssmmessages", "ec2messages"].
  EOT
  type        = set(string)
  default     = []
}

variable "enable_s3_gateway_endpoint" {
  description = "Attach an S3 gateway endpoint to the private route tables."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
