variable "secrets_file_path" {
  type        = string
  description = "Path to the canonical SOPS credentials file holding github configuration (defaults to production credentials)."
  default     = "../../secrets/credentials.sops.yaml"
}

variable "github_token" {
  type        = string
  description = "Personal Access Token for GitHub authentication (sourced from SOPS github.token when null)."
  sensitive   = true
  nullable    = true
  default     = null
}

variable "github_owner" {
  type        = string
  description = "The target GitHub organization or user account (sourced from SOPS github.owner when null)."
  sensitive   = true
  nullable    = true
  default     = null
}


variable "allow_merge_commit" {
  type        = bool
  description = "Whether to allow merge commits on the repository (must be false to enforce linear trunk-based history)."
  default     = false

  validation {
    condition     = var.allow_merge_commit == false
    error_message = "allow_merge_commit must be false. Merge commits violate repository trunk-based development policy."
  }
}

variable "allow_rebase_merge" {
  type        = bool
  description = "Whether to allow rebase merge on the repository (must be false to enforce squash-merge policy)."
  default     = false

  validation {
    condition     = var.allow_rebase_merge == false
    error_message = "allow_rebase_merge must be false. Rebase merges violate repository squash-merge policy."
  }
}

variable "ci_secrets" {
  type        = map(string)
  description = "A map of sensitive secrets to inject into the 'ci' environment."
  sensitive   = true
  default     = {}
}

variable "backup_secrets" {
  type        = map(string)
  description = "A map of sensitive secrets to inject into the 'backup' environment (restricted to main)."
  sensitive   = true
  default     = {}

  validation {
    condition     = !contains(keys(var.backup_secrets), "SOPS_AGE_KEY_CI")
    error_message = "SOPS_AGE_KEY_CI belongs exclusively to the 'ci' environment and must not be injected into 'backup' (R2-CI-01)."
  }

  validation {
    condition     = length(var.backup_secrets) == 0 || length(setintersection(values(local.ci_environment_secrets), values(var.backup_secrets))) == 0
    error_message = "backup_secrets must not share any secret values with the PR-reachable 'ci' environment (R2-CI-01)."
  }
}

variable "ops_secrets" {
  type        = map(string)
  description = "A map of sensitive secrets to inject into the 'ops' environment (restricted to main)."
  sensitive   = true
  default     = {}

  validation {
    condition     = !contains(keys(var.ops_secrets), "SOPS_AGE_KEY_CI")
    error_message = "SOPS_AGE_KEY_CI belongs exclusively to the 'ci' environment and must not be injected into 'ops' (R2-CI-01)."
  }

  validation {
    condition     = length(var.ops_secrets) == 0 || length(setintersection(values(local.ci_environment_secrets), values(var.ops_secrets))) == 0
    error_message = "ops_secrets must not share any secret values with the PR-reachable 'ci' environment (R2-CI-01)."
  }
}

variable "sops_age_key_ci" {
  type        = string
  description = "Override for the single CI age identity uploaded to GitHub. Null (default) reads production SOPS `github.ci_age_key`."
  sensitive   = true
  nullable    = true
  default     = null

  validation {
    condition     = var.sops_age_key_ci == null || var.sops_age_key_ci == "" || can(regex("^AGE-SECRET-KEY-1[0-9A-Z]{58}$", var.sops_age_key_ci))
    error_message = "sops_age_key_ci must be null/empty or exactly one age identity (AGE-SECRET-KEY-1...), not a keyring file."
  }
}

variable "deploy_keys" {
  type = map(object({
    title     = string
    key       = string
    read_only = bool
  }))
  description = "Deploy keys to register on the primary infra repository (overrides SOPS github.config.deploy_keys when non-empty)."
  sensitive   = true
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.deploy_keys : v.read_only == true])
    error_message = "All deploy keys must enforce read_only = true (R2-TF-08)."
  }

  validation {
    condition     = alltrue([for k, v in var.deploy_keys : !can(regex("@", v.key))])
    error_message = "Deploy key public keys must not contain email comments ('@') to prevent PII leakage (R2-TF-08)."
  }
}

variable "allowed_action_patterns" {
  type        = list(string)
  description = "Explicit allowlist of third-party GitHub Action patterns permitted to run in managed repositories (R2-GOV-01)."
  default = [
    "cloudflare/wrangler-action@*",
    "gitleaks/gitleaks-action@*",
    "jdx/mise-action@*",
    "step-security/harden-runner@*",
  ]

  validation {
    condition     = length(var.allowed_action_patterns) > 0 && !contains(var.allowed_action_patterns, "*")
    error_message = "allowed_action_patterns must be non-empty and must not contain a wildcard '*'."
  }
}

variable "enable_prevent_destroy" {
  type        = bool
  description = "Whether to prevent destruction of critical GitHub resources (defaults to true for production safety)."
  default     = true
}

variable "enable_merge_queue" {
  type        = bool
  description = "Override for GitHub Merge Queue on each managed repository's main ruleset. Null (default) enables it on public repositories only, the GitHub Free plan limit."
  default     = null
  nullable    = true
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
