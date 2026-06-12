variable "azure_subscription_id" {
  type        = string
  description = "The Azure subscription ID."
  sensitive   = true
}

variable "state_encryption_passphrase" {
  type        = string
  description = "Passphrase for OpenTofu state encryption (AES-GCM via PBKDF2). Never hardcode — inject via TF_VAR_state_encryption_passphrase environment variable."
  sensitive   = true
}

variable "budget_contact_emails" {
  type        = list(string)
  description = "List of email addresses to notify when budget thresholds are exceeded."
  default     = []
}
