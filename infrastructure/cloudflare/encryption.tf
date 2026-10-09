variable "state_encryption_passphrase" {
  type        = string
  description = "Passphrase for OpenTofu state and plan encryption."
  sensitive   = true
  default     = "homelab-state-encryption-passphrase-default"
}

variable "previous_state_encryption_passphrase" {
  type        = string
  description = "Previous passphrase for OpenTofu state decryption fallback during migration."
  sensitive   = true
  default     = "homelab-state-encryption-passphrase-default"
}

terraform {
  encryption {
    key_provider "pbkdf2" "state_passphrase" {
      passphrase    = var.state_encryption_passphrase
      key_length    = 32
      iterations    = 600000
      hash_function = "sha256"
    }

    key_provider "pbkdf2" "old_state_passphrase" {
      passphrase    = var.previous_state_encryption_passphrase
      key_length    = 32
      iterations    = 600000
      hash_function = "sha256"
    }

    method "aes_gcm" "state_method" {
      keys = key_provider.pbkdf2.state_passphrase
    }

    method "aes_gcm" "old_state_method" {
      keys = key_provider.pbkdf2.old_state_passphrase
    }

    state {
      method   = method.aes_gcm.state_method
      enforced = true

      fallback {
        method = method.aes_gcm.old_state_method
      }
    }

    plan {
      method   = method.aes_gcm.state_method
      enforced = true

      fallback {
        method = method.aes_gcm.old_state_method
      }
    }
  }
}
