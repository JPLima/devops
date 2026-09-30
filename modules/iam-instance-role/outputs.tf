output "role_arn" {
  description = "ARN of the instance role."
  value       = aws_iam_role.instance.arn
}

output "role_name" {
  description = "Name of the instance role."
  value       = aws_iam_role.instance.name
}

output "instance_profile_name" {
  description = "Instance profile to attach to the EC2 instance."
  value       = aws_iam_instance_profile.instance.name
}

output "policy_arn" {
  description = "ARN of the hand-written workload policy."
  value       = aws_iam_policy.workload.arn
}
