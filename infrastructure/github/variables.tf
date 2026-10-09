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

variable "reviewers_for_production" {
  type        = list(string)
  description = "List of GitHub user or team IDs that can approve production deployments."
  default     = []
}

