variable "secrets_file_path" {
  type        = string
  description = "Path to the canonical SOPS credentials file holding NextDNS credentials and sensitive profile config."
  default     = "../../secrets/credentials.sops.yaml"

  validation {
    condition     = can(regex("\\.ya?ml$", var.secrets_file_path))
    error_message = "secrets_file_path must point to a YAML file (.yaml or .yml)."
  }
}

variable "enable_prevent_destroy" {
  type        = bool
  description = "Whether to enforce prevent_destroy on NextDNS profiles (STD-OT-44)."
  default     = true
}

variable "state_encryption_passphrase" {
  type        = string
  description = "State and plan encryption passphrase. Source: production SOPS opentofu.state_encryption_passphrase. No default, so a missing value fails closed."
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(var.state_encryption_passphrase) >= 32
    error_message = "Set TF_VAR_state_encryption_passphrase from SOPS (opentofu.state_encryption_passphrase); it must be at least 32 characters."
  }

  validation {
    condition     = !can(regex("(?i)(default|changeme|placeholder|example)", var.state_encryption_passphrase))
    error_message = "state_encryption_passphrase looks like a placeholder; supply the real value from SOPS."
  }
}
