variable "healthchecksio_api_key" {
  type        = string
  description = "Healthchecks.io API Key for managing checks."
  sensitive   = true
}

variable "default_tags" {
  type        = list(string)
  description = "Default tags applied to healthchecks."
  default     = ["homelab", "backup", "restic"]

  validation {
    condition     = contains(var.default_tags, "homelab")
    error_message = "default_tags must include the mandatory 'homelab' project tag."
  }
}

variable "check_tags" {
  type        = list(string)
  description = "Additional project tags applied across all healthchecks (must include 'homelab')."
  default     = ["homelab", "backup", "restic"]

  validation {
    condition     = contains(var.check_tags, "homelab")
    error_message = "check_tags must include the mandatory 'homelab' project tag."
  }
}

variable "healthcheck_timeout" {
  type        = number
  description = "Execution interval / timeout in seconds between ping events (60s to 86400s / 24h)."
  default     = 86400

  validation {
    condition     = var.healthcheck_timeout >= 60 && var.healthcheck_timeout <= 86400
    error_message = "healthcheck_timeout must be between 60 and 86400 seconds (max 24 hours)."
  }
}

variable "healthcheck_grace" {
  type        = number
  description = "Grace period in seconds before alerting on a missed ping (300s / 5m to 14400s / 4h)."
  default     = 7200

  validation {
    condition     = var.healthcheck_grace >= 300 && var.healthcheck_grace <= 14400
    error_message = "healthcheck_grace must be between 300 and 14400 seconds (5m to 4h)."
  }
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

variable "compose_targets" {
  type        = list(string)
  description = "Logical Docker Compose target IDs (one per host, e.g., homelab, gcp, oci-1)."
  default     = ["homelab", "gcp", "oci-1"]
  sensitive   = true

  validation {
    condition     = length(var.compose_targets) > 0 && alltrue([for t in var.compose_targets : length(trimspace(t)) > 0 && can(regex("^[a-z0-9][a-z0-9-]*$", t))])
    error_message = "compose_targets must be non-empty and every target ID must match ^[a-z0-9][a-z0-9-]*$."
  }

  validation {
    condition     = length(distinct(var.compose_targets)) == length(var.compose_targets)
    error_message = "compose_targets must not contain duplicate target IDs."
  }
}
