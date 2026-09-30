variable "name" {
  description = "Name prefix for the instance and its volumes."
  type        = string
}

variable "vpc_id" {
  description = "VPC the instance belongs to."
  type        = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR, used to scope egress to the VPC endpoints."
  type        = string
}

variable "subnet_id" {
  description = "Private subnet to launch into."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "instance_profile_name" {
  description = "Instance profile granting the workload its permissions."
  type        = string
}

variable "kms_key_arn" {
  description = "Customer-managed key for the EBS volumes."
  type        = string
}

variable "root_volume_size" {
  description = "Root volume size in GiB."
  type        = number
  default     = 20
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
