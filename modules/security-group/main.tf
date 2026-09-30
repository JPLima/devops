# A security group whose rules are each a separate resource.
#
# Why not inline ingress/egress blocks: they live as one attribute of one
# resource, so editing any CIDR rewrites the whole set and the plan churns
# rules that did not change.
#
# Why not count over a list: removing the second of four entries shifts the
# indices of the remaining three, so Terraform destroys and recreates three
# rules to remove one.
#
# for_each over a map keyed by name gives every rule a stable address. Adding
# or removing a CIDR produces a plan with exactly one create or one destroy.

resource "aws_security_group" "this" {
  # name_prefix, not name: a rename would otherwise deadlock against a group
  # still attached to an ENI.
  name_prefix = "${var.name}-"
  description = var.description
  vpc_id      = var.vpc_id

  # No ingress or egress blocks here on purpose. Mixing them with the
  # standalone rule resources below makes the two fight on every plan, each
  # reverting the other.

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = var.ingress_rules

  security_group_id = aws_security_group.this.id
  description       = each.value.description
  ip_protocol       = each.value.ip_protocol

  # AWS rejects ports on an all-protocols rule.
  from_port = each.value.ip_protocol == "-1" ? null : each.value.from_port
  to_port   = each.value.ip_protocol == "-1" ? null : each.value.to_port

  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.referenced_security_group_id

  # The console lists these rules by their sgr- id only. The tag is what makes
  # a rule recognisable there.
  tags = merge(var.tags, { Name = each.key })
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = var.egress_rules

  security_group_id = aws_security_group.this.id
  description       = each.value.description
  ip_protocol       = each.value.ip_protocol

  from_port = each.value.ip_protocol == "-1" ? null : each.value.from_port
  to_port   = each.value.ip_protocol == "-1" ? null : each.value.to_port

  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.referenced_security_group_id

  tags = merge(var.tags, { Name = each.key })
}
