variable "name" {
  description = "Base name for the security group. Used as a name_prefix, so the group gets a unique suffix."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,99}$", var.name))
    error_message = "name must be lowercase alphanumeric with hyphens, starting with a letter or digit."
  }
}

variable "description" {
  description = "Description of the security group. AWS does not allow this to be changed after creation."
  type        = string
}

variable "vpc_id" {
  description = "VPC the security group belongs to."
  type        = string
}

variable "ingress_rules" {
  description = <<-EOT
    Inbound rules, keyed by a stable human-readable name such as
    "https-from-office-lisbon". The key becomes the Terraform resource address,
    so adding or removing an entry only ever touches that one rule.

    Each rule must set exactly one source: cidr_ipv4, cidr_ipv6,
    prefix_list_id or referenced_security_group_id. That is an AWS constraint
    on aws_vpc_security_group_ingress_rule, and it is what makes one rule per
    resource possible.
  EOT

  type = map(object({
    description                  = string
    ip_protocol                  = string
    from_port                    = optional(number)
    to_port                      = optional(number)
    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    prefix_list_id               = optional(string)
    referenced_security_group_id = optional(string)
  }))

  default = {}

  validation {
    condition = alltrue([
      for key, rule in var.ingress_rules :
      length([
        for source in [
          rule.cidr_ipv4,
          rule.cidr_ipv6,
          rule.prefix_list_id,
          rule.referenced_security_group_id,
        ] : source if source != null
      ]) == 1
    ])
    error_message = "Each ingress rule must set exactly one of cidr_ipv4, cidr_ipv6, prefix_list_id or referenced_security_group_id."
  }

  validation {
    condition = alltrue([
      for key, rule in var.ingress_rules :
      rule.ip_protocol == "-1" || (rule.from_port != null && rule.to_port != null)
    ])
    error_message = "Each ingress rule must set from_port and to_port unless ip_protocol is \"-1\"."
  }
}

variable "egress_rules" {
  description = <<-EOT
    Outbound rules, keyed the same way as ingress_rules.

    AWS attaches an allow-all egress rule to every new security group. This
    module does not manage that rule, so define the egress you actually want
    here and remove the default out of band if your account does not already
    do so.
  EOT

  type = map(object({
    description                  = string
    ip_protocol                  = string
    from_port                    = optional(number)
    to_port                      = optional(number)
    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    prefix_list_id               = optional(string)
    referenced_security_group_id = optional(string)
  }))

  default = {}

  validation {
    condition = alltrue([
      for key, rule in var.egress_rules :
      length([
        for source in [
          rule.cidr_ipv4,
          rule.cidr_ipv6,
          rule.prefix_list_id,
          rule.referenced_security_group_id,
        ] : source if source != null
      ]) == 1
    ])
    error_message = "Each egress rule must set exactly one of cidr_ipv4, cidr_ipv6, prefix_list_id or referenced_security_group_id."
  }

  validation {
    condition = alltrue([
      for key, rule in var.egress_rules :
      rule.ip_protocol == "-1" || (rule.from_port != null && rule.to_port != null)
    ])
    error_message = "Each egress rule must set from_port and to_port unless ip_protocol is \"-1\"."
  }
}

variable "tags" {
  description = "Tags applied to the security group and to every rule."
  type        = map(string)
  default     = {}
}
