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
  description = "Number of availability zones to spread subnets across."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "az_count must be between 2 and 4. Two is the minimum for an RDS subnet group."
  }
}

variable "subnet_newbits" {
  description = <<-EOT
    Bits added to the VPC prefix length to size each subnet. With a /16 VPC,
    8 gives /24 subnets. Must leave room for 2 * az_count subnets.
  EOT
  type        = number
  default     = 8
}

variable "map_public_ip_on_launch" {
  description = <<-EOT
    Whether instances launched in the public subnets get a public IP without
    asking. False by default: a public address should be a decision, not a
    default. Set true for a public web tier.
  EOT
  type        = bool
  default     = false
}

variable "enable_nat_gateway" {
  description = "Create NAT gateways so private subnets reach the internet."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = <<-EOT
    Route every private subnet through one NAT gateway instead of one per AZ.
    Cheaper, but the NAT becomes a single point of failure and a zone outage
    takes egress with it. Suitable for non-production environments.
  EOT
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
  description = <<-EOT
    Retention for the flow log group. One year by default, the floor most
    compliance regimes expect. Flow logs are voluminous, so this is the first
    dial to turn if the CloudWatch bill matters more than the lookback window.
  EOT
  type        = number
  default     = 365
}

variable "flow_logs_traffic_type" {
  description = <<-EOT
    ACCEPT, REJECT or ALL. ALL by default: accepted traffic is what tells you
    what an intruder reached, where rejects only tell you what they failed to
    reach.
  EOT
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
    Interface endpoint service names, without the com.amazonaws.<region>.
    prefix. ["ssm", "ssmmessages", "ec2messages"] is what Session Manager
    needs to reach a private instance without a route to the internet;
    ssmmessages carries the session channel, and without it a session opens
    and then hangs.

    Empty means no interface endpoints.
  EOT
  type        = set(string)
  default     = []
}

variable "enable_s3_gateway_endpoint" {
  description = <<-EOT
    Attach an S3 gateway endpoint to the private route tables. Gateway
    endpoints are free, where an interface endpoint for S3 bills per hour and
    per gigabyte.
  EOT
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
