output "vpc_id" {
  description = "VPC id."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet ids, ordered by availability zone."
  value       = [for az in local.azs : aws_subnet.public[az].id]
}

output "private_subnet_ids" {
  description = "Private subnet ids, ordered by availability zone."
  value       = [for az in local.azs : aws_subnet.private[az].id]
}

output "availability_zones" {
  description = "Availability zones the subnets were placed in."
  value       = local.azs
}

output "nat_gateway_public_ips" {
  description = "Public IPs of the NAT gateways, useful for allow-listing outbound traffic downstream."
  value       = aws_eip.nat[*].public_ip
}

output "flow_log_group_name" {
  description = "CloudWatch log group receiving flow logs, null when they are disabled."
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.flow_logs[0].name : null
}

output "flow_log_group_arn" {
  description = "ARN of the flow log group, null when flow logs are disabled."
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.flow_logs[0].arn : null
}

output "endpoints_security_group_id" {
  description = "Security group attached to the interface endpoints, null when there are none."
  value       = local.needs_endpoint_security_group ? module.endpoints_sg[0].id : null
}

output "interface_endpoint_ids" {
  description = "Map of service name to interface endpoint id."
  value       = { for name, endpoint in aws_vpc_endpoint.interface : name => endpoint.id }
}
