variable "name" {
  description = "Name prefix for the recorder, channel and rules."
  type        = string
}

variable "bucket_name" {
  description = "Globally unique name for the bucket AWS Config delivers to."
  type        = string
}

variable "kms_key_arn" {
  description = "Key encrypting the delivery bucket."
  type        = string
}

variable "expiration_days" {
  description = "Days before configuration snapshots expire."
  type        = number
  default     = 365
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
