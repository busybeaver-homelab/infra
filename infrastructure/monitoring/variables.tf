variable "healthchecksio_api_key" {
  type        = string
  description = "Healthchecks.io API Key for managing checks."
  sensitive   = true
}

variable "default_tags" {
  type        = list(string)
  description = "Default tags applied to healthchecks."
  default     = ["homelab", "backup", "restic"]
}
