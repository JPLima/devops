resource "aws_security_group" "this" {
  name_prefix = "${var.name}-"
  description = var.description
  vpc_id      = var.vpc_id

  # No inline ingress/egress. They conflict with the standalone rule
  # resources below and the two revert each other on every apply.

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

  # The console only shows the sgr- id without this.
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
