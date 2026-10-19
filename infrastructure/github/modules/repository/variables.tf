variable "repository_name" {
  type        = string
  description = "The name of the target GitHub repository."
  sensitive   = true
}

variable "description" {
  type        = string
  description = "Optional description of the repository (defaults to empty description when null)."
  nullable    = true
  default     = null
}

variable "topics" {
  type        = list(string)
  description = "A list of topics of the repository."
  default     = []
}

variable "visibility" {
  type        = string
  description = "The visibility of the target GitHub repository (public, private, or internal)."
  default     = "public"

  validation {
    condition     = contains(["public", "private", "internal"], var.visibility)
    error_message = "visibility must be one of: public, private, internal."
  }
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
  description = "A map of sensitive secrets to inject into the 'ci' environment (reachable from PR jobs: synthetic or CI-only material only)."
  sensitive   = true
  default     = {}

  validation {
    condition     = !anytrue([for k in keys(var.ci_secrets) : can(regex("(?i)(PASSPHRASE|TOFU_ENCRYPTION)", k))])
    error_message = "The OpenTofu state passphrase must never be distributed to the ci environment (PR jobs can reach it)."
  }

  validation {
    condition     = !contains(keys(var.ci_secrets), "SOPS_AGE_KEY_CI") || can(regex("^AGE-SECRET-KEY-1[0-9A-Z]{58}$", var.ci_secrets["SOPS_AGE_KEY_CI"]))
    error_message = "SOPS_AGE_KEY_CI must be exactly one age identity (no keyring files, no decoys). Add it to production SOPS as github.ci_age_key."
  }
}

variable "backup_secrets" {
  type        = map(string)
  description = "A map of sensitive secrets to inject into the 'backup' environment (restricted to main)."
  sensitive   = true
  default     = {}

  validation {
    condition     = !anytrue([for k in keys(var.backup_secrets) : can(regex("(?i)(PASSPHRASE|TOFU_ENCRYPTION)", k))])
    error_message = "The OpenTofu state passphrase must never be distributed to GitHub environments."
  }

  validation {
    condition     = !contains(keys(var.backup_secrets), "SOPS_AGE_KEY_CI")
    error_message = "SOPS_AGE_KEY_CI belongs exclusively to the 'ci' environment and must not be injected into 'backup' (R2-CI-01)."
  }
}

variable "ops_secrets" {
  type        = map(string)
  description = "A map of sensitive secrets to inject into the 'ops' environment (restricted to main)."
  sensitive   = true
  default     = {}

  validation {
    condition     = !anytrue([for k in keys(var.ops_secrets) : can(regex("(?i)(PASSPHRASE|TOFU_ENCRYPTION)", k))])
    error_message = "The OpenTofu state passphrase must never be distributed to GitHub environments."
  }

  validation {
    condition     = !contains(keys(var.ops_secrets), "SOPS_AGE_KEY_CI")
    error_message = "SOPS_AGE_KEY_CI belongs exclusively to the 'ci' environment and must not be injected into 'ops' (R2-CI-01)."
  }
}

variable "deploy_keys" {
  type = map(object({
    title     = string
    key       = string
    read_only = bool
  }))
  description = "A map of deploy keys to register on the repository."
  sensitive   = true
  default     = {}

  # Note: read-write permissions (`read_only = false`) are permitted and required on the deploy key to push code.

  validation {
    condition     = alltrue([for k, v in var.deploy_keys : !can(regex("@", v.key))])
    error_message = "Deploy key public keys must not contain email comments ('@') to prevent PII leakage (R2-TF-08)."
  }
}

variable "allowed_action_patterns" {
  type        = list(string)
  description = "Explicit allowlist of third-party GitHub Action patterns permitted to run in the repository (R2-GOV-01)."
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
  description = "Whether to prevent destruction of the repository resource (defaults to true for production safety)."
  default     = true
}

variable "enable_merge_queue" {
  type        = bool
  description = "Whether to enable GitHub Merge Queue on the main branch ruleset. Defaults to true when visibility is public and false otherwise (GitHub Free org plans only support merge queues on public repositories)."
  default     = null
  nullable    = true
}

