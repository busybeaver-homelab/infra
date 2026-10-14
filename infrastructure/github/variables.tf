variable "secrets_file_path" {
  type        = string
  description = "Path to the canonical SOPS credentials file holding github configuration (defaults to production credentials)."
  default     = "../../secrets/credentials.sops.yaml"
}

variable "github_token" {
  type        = string
  description = "Personal Access Token for GitHub authentication (overrides SOPS if provided)."
  sensitive   = true
  default     = ""
}

variable "github_owner" {
  type        = string
  description = "The target GitHub organization or user account (overrides SOPS if provided)."
  sensitive   = true
  default     = ""
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
  description = "A map of sensitive secrets to inject into the 'backup' environment."
  sensitive   = true
  default     = {}
}

variable "sops_age_key_ci" {
  type        = string
  description = "Override for the single CI age identity uploaded to GitHub. Empty (default) reads production SOPS `github.ci_age_key`."
  sensitive   = true
  default     = ""

  validation {
    condition     = var.sops_age_key_ci == "" || can(regex("^AGE-SECRET-KEY-1[0-9A-Z]{58}$", var.sops_age_key_ci))
    error_message = "sops_age_key_ci must be empty or exactly one age identity (AGE-SECRET-KEY-1...), not a keyring file."
  }
}

variable "deploy_keys" {
  type = map(object({
    title     = string
    key       = string
    read_only = bool
  }))
  description = "Deploy keys to register on the primary infra repository."
  default = {
    "work-laptop" = {
      title     = "work-laptop"
      key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINhE5DoHICY85bnMIzXRGkggJ97ekZaJtzpQ6I7JgfF0 jmollner@liveperson.com"
      read_only = false
    }
  }
}

variable "enable_prevent_destroy" {
  type        = bool
  description = "Whether to prevent destruction of critical GitHub resources (defaults to true for production safety)."
  default     = true
}

