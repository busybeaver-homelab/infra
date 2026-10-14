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
variable "default_labels" {
  type        = map(string)
  description = "Default labels applied to all GCP resources. Must include project = 'homelab'."
  default = {
    project = "homelab"
  }

  validation {
    condition     = lookup(var.default_labels, "project", "") == "homelab"
    error_message = "The 'project' label must be defined in default_labels and set to 'homelab'."
  }
}

variable "gcp_instance_type" {
  type        = string
  description = "The GCP compute instance machine type. Strictly restricted to the Always Free Tier shape: e2-micro."
  default     = "e2-micro"
  sensitive   = false

  validation {
    condition     = var.gcp_instance_type == "e2-micro"
    error_message = "Instance type must be 'e2-micro' to comply with GCP Always Free Tier policy."
  }
}

variable "gcp_boot_disk_size_gb" {
  type        = number
  description = "The boot disk size in GB. Strictly restricted to the Always Free Tier allowance: 10 to 30 GB."
  default     = 30
  sensitive   = false

  validation {
    condition     = var.gcp_boot_disk_size_gb >= 10 && var.gcp_boot_disk_size_gb <= 30
    error_message = "Boot disk size must be between 10 and 30 GB to comply with GCP Always Free Tier policy."
  }
}

variable "gcp_boot_disk_type" {
  type        = string
  description = "The persistent disk type. Strictly restricted to the Always Free Tier type: pd-standard."
  default     = "pd-standard"
  sensitive   = false

  validation {
    condition     = var.gcp_boot_disk_type == "pd-standard"
    error_message = "Boot disk type must be 'pd-standard' to comply with GCP Always Free Tier policy."
  }
}

variable "gcp_billing_account_id" {
  type        = string
  description = "The GCP billing account ID (e.g., 012345-6789AB-CDEF01) for budget and spend alert management. Leave empty to skip budget creation."
  default     = ""
  sensitive   = true

  validation {
    condition     = var.gcp_billing_account_id == "" || can(regex("^[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$", var.gcp_billing_account_id))
    error_message = "GCP billing account ID must be formatted as 6 alphanumeric characters separated by hyphens (e.g., 012345-6789AB-CDEF01), or empty."
  }
}

variable "state_encryption_passphrase" {
  type        = string
  description = "State and plan encryption passphrase. Source: production SOPS opentofu.state_encryption_passphrase. No default, so a missing value fails closed."
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(var.state_encryption_passphrase) >= 32
    error_message = "Set TF_VAR_state_encryption_passphrase from SOPS (opentofu.state_encryption_passphrase); it must be at least 32 characters."
  }

  validation {
    condition     = !can(regex("(?i)(default|changeme|placeholder|example)", var.state_encryption_passphrase))
    error_message = "state_encryption_passphrase looks like a placeholder; supply the real value from SOPS."
  }
}
