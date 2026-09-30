output "instance_id" {
  description = "Instance id. Use it to open a session: aws ssm start-session --target <id>"
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Private IP inside the VPC."
  value       = aws_instance.this.private_ip
}

output "private_dns" {
  description = "Private DNS name inside the VPC."
  value       = aws_instance.this.private_dns
}

output "security_group_id" {
  description = "Security group attached to the instance."
  value       = module.security_group.id
}

output "availability_zone" {
  description = "Availability zone the instance landed in."
  value       = aws_instance.this.availability_zone
}
