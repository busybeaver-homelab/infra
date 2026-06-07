variable "gcp_project_id" {
  type        = string
  description = "The Google Cloud project ID."
  sensitive   = true
}

variable "gcp_region" {
  type        = string
  description = "The primary Google Cloud region."
  default     = "us-central1"
  sensitive   = false
}

variable "state_encryption_passphrase" {
  type        = string
  description = "Passphrase for OpenTofu state encryption (AES-GCM via PBKDF2). Never hardcode — inject via TF_VAR_state_encryption_passphrase environment variable."
  sensitive   = true
}
