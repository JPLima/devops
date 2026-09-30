variable "alias" {
  description = "Alias for the key, without the \"alias/\" prefix."
  type        = string
}

variable "description" {
  description = "What this key encrypts. Keys are cheap; a key per purpose keeps the blast radius small and the key policy readable."
  type        = string
}

variable "service_principals" {
  description = <<-EOT
    AWS service principals allowed to use the key, for example
    ["logs.eu-west-1.amazonaws.com"]. Services cannot assume a role, so they
    need a grant in the key policy itself.
  EOT
  type        = list(string)
  default     = []
}

variable "service_condition" {
  description = <<-EOT
    Optional condition narrowing the service grant, as a single object with
    test, variable and values. Without one, any resource of that service in
    the account can use the key.
  EOT
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
