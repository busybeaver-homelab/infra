variable "repository_name" {
  type        = string
  description = "The name of the target GitHub repository."
  sensitive   = true
}

variable "description" {
  type        = string
  description = "A description of the repository."
  default     = ""
}

variable "topics" {
  type        = list(string)
  description = "A list of topics of the repository."
  default     = []
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

variable "deploy_keys" {
  type = map(object({
    title     = string
    key       = string
    read_only = bool
  }))
  description = "A map of deploy keys to register on the repository."
  default     = {}
}

