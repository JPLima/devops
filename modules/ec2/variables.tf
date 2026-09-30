variable "name" {
  description = "Name prefix for the instance and its volumes."
  type        = string
}

variable "subnet_id" {
  description = "Subnet to launch the instance in."
  type        = string
}

variable "security_group_ids" {
  description = <<-EOT
    Security groups to attach. Build them with the security-group module and
    pass the ids in; this module does not create them, so one instance can
    share a group with another and the group's lifecycle is not tied to the
    instance's.
  EOT
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = <<-EOT
    AMI to launch. Null resolves the latest Amazon Linux 2023 image through a
    data source, which keeps the module portable across regions.
  EOT
  type        = string
  default     = null
}

variable "associate_public_ip_address" {
  description = <<-EOT
    Give the instance a public IP. False by default: reachable from the
    internet should be a decision, not an inherited default. Only meaningful
    in a public subnet.
  EOT
  type        = bool
  default     = false
}

variable "root_volume_size" {
  description = "Root volume size in GiB."
  type        = number
  default     = 20
}

variable "kms_key_arn" {
  description = <<-EOT
    Customer-managed key for the root volume. Null uses the AWS-managed EBS
    key; the volume is encrypted either way, but an AWS-managed key's policy
    and rotation cannot be audited.
  EOT
  type        = string
  default     = null
}

variable "iam_instance_profile" {
  description = "Name of an instance profile to attach. Null means no role."
  type        = string
  default     = null
}

variable "user_data" {
  description = "Cloud-init script. Changes replace the instance."
  type        = string
  default     = null
}

variable "detailed_monitoring" {
  description = "One-minute CloudWatch metrics instead of five."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the instance and its volumes."
  type        = map(string)
  default     = {}
}
