variable "gcp_project_id" {
  type        = string
  description = "The Google Cloud project ID."
  sensitive   = true
}

variable "gcp_region" {
  type        = string
  description = "The primary Google Cloud region. Must be in the GCP Always Free Tier eligible regions: us-central1, us-east1, us-west1."
  default     = "us-central1"
  sensitive   = false

  validation {
    condition     = contains(["us-central1", "us-east1", "us-west1"], var.gcp_region)
    error_message = "The gcp_region must be one of the Always Free tier regions: us-central1, us-east1, us-west1."
  }
}


