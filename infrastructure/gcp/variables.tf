variable "gcp_project_id" {
  type        = string
  description = "The Google Cloud project ID."
  sensitive   = true
}

variable "gcp_region" {
  type        = string
  description = "The primary Google Cloud region."
  default     = "us-central1"
  sensitive   = false
}


