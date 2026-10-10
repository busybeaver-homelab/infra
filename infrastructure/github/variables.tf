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
  description = "CI Age private key override for GitHub Actions environment secrets."
  sensitive   = true
  default     = ""
}

variable "sops_age_key_file" {
  type        = string
  description = "Path to the local Age keys file containing the CI private key."
  default     = "~/.config/sops/age/keys.txt"
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

