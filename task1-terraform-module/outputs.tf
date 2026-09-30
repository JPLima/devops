output "environment" {
  description = "Workspace this state belongs to."
  value       = terraform.workspace
}

output "vpc_id" {
  description = "VPC id."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet ids."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet ids."
  value       = module.vpc.private_subnet_ids
}

output "ec2_public_ip" {
  description = "Public IP of the web instance."
  value       = module.ec2.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS name of the web instance."
  value       = module.ec2.public_dns
}

output "ec2_private_dns" {
  description = "Private DNS name of the web instance."
  value       = module.ec2.private_dns
}

output "rds_endpoint" {
  description = "Database endpoint, host and port. Not sensitive: it is a hostname, and it is unreachable outside the VPC."
  value       = module.rds.endpoint
}

output "rds_address" {
  description = "Database hostname."
  value       = module.rds.address
}

output "rds_port" {
  description = "Database port."
  value       = module.rds.port
}

output "web_security_group_id" {
  description = "Web tier security group id."
  value       = module.web_sg.id
}

output "web_ingress_rule_ids" {
  description = "Map of web tier rule name to AWS rule id, one entry per allow-listed network."
  value       = module.web_sg.ingress_rule_ids
}

output "db_security_group_id" {
  description = "Database tier security group id."
  value       = module.db_sg.id
}
