variable "name" {
  description = "Name prefix for the instance and its volumes."
  type        = string
}

variable "subnet_id" {
  description = "Subnet to launch the instance in."
  type        = string
}

variable "security_group_ids" {
  description = "Security groups to attach."
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "associate_public_ip_address" {
  description = "Give the instance a public IP. Only meaningful in a public subnet."
  type        = bool
  default     = true
}

variable "root_volume_size" {
  description = "Root volume size in GiB."
  type        = number
  default     = 20
}

variable "kms_key_arn" {
  description = <<-EOT
    Customer-managed key for the root volume. Leave null to use the AWS-managed
    EBS key; the volume is encrypted either way.
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

variable "tags" {
  description = "Tags applied to the instance and its volumes."
  type        = map(string)
  default     = {}
}
