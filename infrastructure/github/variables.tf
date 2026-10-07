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

