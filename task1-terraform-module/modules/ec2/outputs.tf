output "instance_id" {
  description = "EC2 instance id."
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "Public IP, null when the instance has none."
  value       = aws_instance.this.public_ip
}

output "public_dns" {
  description = "Public DNS name, empty when the instance has no public IP."
  value       = aws_instance.this.public_dns
}

output "private_ip" {
  description = "Private IP inside the VPC."
  value       = aws_instance.this.private_ip
}

output "private_dns" {
  description = "Private DNS name inside the VPC."
  value       = aws_instance.this.private_dns
}

output "ami_id" {
  description = "AMI the instance was launched from."
  value       = aws_instance.this.ami
}

output "availability_zone" {
  description = "Availability zone the instance landed in."
  value       = aws_instance.this.availability_zone
}
