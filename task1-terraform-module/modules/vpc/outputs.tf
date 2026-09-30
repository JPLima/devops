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
