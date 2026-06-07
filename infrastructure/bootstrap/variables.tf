variable "gcp_project_id" {
  type        = string
  description = "The Google Cloud project ID to scaffold resources in."
  sensitive   = true
}

variable "gcp_region" {
  type        = string
  description = "The primary Google Cloud region."
  default     = "us-central1"
  sensitive   = false
}

variable "state_bucket_name" {
  type        = string
  description = "The name of the GCS bucket for remote state storage."
  sensitive   = true
}
