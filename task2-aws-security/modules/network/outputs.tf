output "vpc_id" {
  description = "VPC id."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet ids. They hold the NAT gateways and nothing else."
  value       = [for az in local.azs : aws_subnet.public[az].id]
}

output "private_subnet_ids" {
  description = "Private subnet ids."
  value       = [for az in local.azs : aws_subnet.private[az].id]
}

output "flow_log_group_name" {
  description = "CloudWatch log group receiving VPC flow logs."
  value       = aws_cloudwatch_log_group.flow_logs.name
}

output "flow_log_group_arn" {
  description = "ARN of the flow log group."
  value       = aws_cloudwatch_log_group.flow_logs.arn
}

output "endpoints_security_group_id" {
  description = "Security group attached to the interface endpoints."
  value       = module.endpoints_sg.id
}
