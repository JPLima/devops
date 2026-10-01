variable "alias" {
  description = "Alias for the key, without the \"alias/\" prefix."
  type        = string
}

variable "description" {
  description = "What this key encrypts."
  type        = string
}

variable "service_principals" {
  description = <<-EOT
    Service principals allowed to use the key, e.g. ["logs.eu-west-1.amazonaws.com"].
    Services cannot assume a role, so they need a grant in the key policy.
  EOT
  type        = list(string)
  default     = []
}

variable "service_condition" {
  description = "Condition narrowing the service grant. Without one, any resource of that service can use the key."
  type = object({
    test     = string
    variable = string
    values   = list(string)
  })
  default = null
}

variable "deletion_window_in_days" {
  description = "Waiting period before a scheduled deletion takes effect."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to the key."
  type        = map(string)
  default     = {}
}
