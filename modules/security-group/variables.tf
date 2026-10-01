variable "name" {
  description = "Base name. Used as a name_prefix, so the group gets a unique suffix."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,99}$", var.name))
    error_message = "name must be lowercase alphanumeric with hyphens, starting with a letter or digit."
  }
}

variable "description" {
  description = "Group description. AWS will not let this change after creation."
  type        = string
}

variable "vpc_id" {
  description = "VPC the security group belongs to."
  type        = string
}

variable "ingress_rules" {
  description = <<-EOT
    Inbound rules keyed by name, e.g. "https-from-office-lisbon". The key is
    the Terraform address, so adding or removing an entry touches only that
    rule. Each rule sets exactly one of cidr_ipv4, cidr_ipv6, prefix_list_id
    or referenced_security_group_id.
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
    Outbound rules, keyed like ingress_rules. AWS attaches an allow-all egress
    rule to every new group and this module does not manage it, so declare
    what you want here and handle the default separately.
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
