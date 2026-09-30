output "id" {
  description = "Security group id, for use as referenced_security_group_id in other rules."
  value       = aws_security_group.this.id
}

output "arn" {
  description = "Security group ARN."
  value       = aws_security_group.this.arn
}

output "name" {
  description = "Generated security group name, including the prefix suffix."
  value       = aws_security_group.this.name
}

output "ingress_rule_ids" {
  description = "Map of rule key to the AWS rule id, so a caller can reference an individual rule."
  value       = { for key, rule in aws_vpc_security_group_ingress_rule.this : key => rule.security_group_rule_id }
}

output "egress_rule_ids" {
  description = "Map of rule key to the AWS rule id."
  value       = { for key, rule in aws_vpc_security_group_egress_rule.this : key => rule.security_group_rule_id }
}
