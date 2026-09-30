variable "name" {
  description = "Name of the secret."
  type        = string
}

variable "description" {
  description = "What the secret holds."
  type        = string
}

variable "kms_key_arn" {
  description = "Key encrypting the secret."
  type        = string
}

variable "username" {
  description = "Username stored alongside the generated password."
  type        = string
}

variable "password_length" {
  description = "Length of the generated password."
  type        = number
  default     = 32
}

variable "recovery_window_in_days" {
  description = "Days a deleted secret can be restored. Zero deletes immediately, which is rarely what you want."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to the secret."
  type        = map(string)
  default     = {}
}
