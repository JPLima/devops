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

variable "enable_nat_gateway" {
  description = "Create NAT gateways so private subnets reach the internet."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = <<-EOT
    Route every private subnet through one NAT gateway instead of one per AZ.
    Cheaper, but the NAT becomes a single point of failure. Suitable for
    non-production environments.
  EOT
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
