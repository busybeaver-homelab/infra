variable "github_token" {
  type        = string
  description = "Personal Access Token for GitHub authentication."
  sensitive   = true
}

variable "github_owner" {
  type        = string
  description = "The target GitHub organization or user account."
  sensitive   = true
}

variable "repository_name" {
  type        = string
  description = "The name of the target GitHub repository."
  default     = "homelab-infra"
  sensitive   = true
}

variable "state_encryption_passphrase" {
  type        = string
  description = "Passphrase for OpenTofu state encryption (AES-GCM via PBKDF2). Never hardcode — inject via TF_VAR_state_encryption_passphrase environment variable."
  sensitive   = true
}
