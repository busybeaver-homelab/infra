variable "gcp_project_id" {
  type        = string
  description = "The Google Cloud project ID."
  sensitive   = true

  validation {
    condition     = length(trimspace(var.gcp_project_id)) > 0
    error_message = "The gcp_project_id must not be empty."
  }
}

variable "gcp_region" {
  type        = string
  description = "The primary Google Cloud region. Must be in the GCP Always Free Tier eligible regions: us-central1, us-east1, us-west1."
  default     = "us-central1"
  sensitive   = false

  validation {
    # Always Free e2-micro & 5 GB regional Standard Storage: us-central1, us-east1, us-west1.
    # Source: https://cloud.google.com/free/docs/free-cloud-features#compute (verified 2026-10-14)
    condition     = contains(["us-central1", "us-east1", "us-west1"], var.gcp_region)
    error_message = "The gcp_region must be one of the Always Free tier regions: us-central1, us-east1, us-west1."
  }
}

variable "gcp_zone" {
  type        = string
  description = "The Google Cloud availability zone within gcp_region (e.g., us-central1-a)."
  default     = "us-central1-a"
  sensitive   = false

  validation {
    condition     = can(regex("^(us-central1|us-east1|us-west1)-[a-f]$", var.gcp_zone)) && startswith(var.gcp_zone, "${var.gcp_region}-")
    error_message = "The gcp_zone must be a valid zone inside the selected Always Free gcp_region (e.g., us-central1-a)."
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
    condition     = length(trimspace(var.gcp_instance_type)) > 0
    error_message = "The gcp_instance_type must not be empty."
  }
}

variable "gcp_boot_disk_size_gb" {
  type        = number
  description = "The boot disk size in GB. Strictly restricted to the Always Free Tier allowance: 10 to 30 GB."
  default     = 30
  sensitive   = false

  validation {
    condition     = var.gcp_boot_disk_size_gb >= 10
    error_message = "Boot disk size must be at least 10 GB (Ubuntu minimal boot image requirement)."
  }
}

variable "gcp_boot_disk_type" {
  type        = string
  description = "The persistent disk type. Strictly restricted to the Always Free Tier type: pd-standard."
  default     = "pd-standard"
  sensitive   = false

  validation {
    condition     = length(trimspace(var.gcp_boot_disk_type)) > 0
    error_message = "The gcp_boot_disk_type must not be empty."
  }
}

variable "gcp_network_tier" {
  type        = string
  description = "Network Service Tier for the external IPv4 access config. Strictly restricted to STANDARD."
  default     = "STANDARD"
  sensitive   = false

  validation {
    condition     = contains(["STANDARD", "PREMIUM"], var.gcp_network_tier)
    error_message = "Network tier must be a valid GCP network service tier ('STANDARD' or 'PREMIUM')."
  }
}

variable "gcp_billing_account_id" {
  type        = string
  description = "The GCP billing account ID (e.g., 012345-6789AB-CDEF01) for mandatory $1 budget and spend alert management."
  sensitive   = true
  nullable    = false

  validation {
    condition     = can(regex("^[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$", var.gcp_billing_account_id))
    error_message = "GCP billing account ID is mandatory (STD-OT-41) and must be formatted as 6 uppercase alphanumeric characters separated by hyphens (e.g., 012345-6789AB-CDEF01)."
  }
}

variable "budget_alert_recipients" {
  type        = list(string)
  description = "Optional list of email addresses to receive GCP budget alert notifications (overrides SOPS gcp.config.budget_alert_recipients if non-empty)."
  sensitive   = true
  default     = []

  validation {
    condition     = alltrue([for r in var.budget_alert_recipients : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", r))])
    error_message = "All entries in budget_alert_recipients must be valid email addresses."
  }

  validation {
    condition     = alltrue([for r in var.budget_alert_recipients : !can(regex("(?i)@example\\.(com|org|net)$", r))])
    error_message = "budget_alert_recipients must not use placeholder @example.com/.org/.net domains (STD-OT-41)."
  }
}

variable "vpc_subnet_cidr" {
  type        = string
  description = "IPv4 CIDR block for the private GCP compute subnetwork (sourced from SOPS gcp.subnet_cidr when null)."
  sensitive   = true
  nullable    = true
  default     = null

  validation {
    condition     = var.vpc_subnet_cidr == null || (trimspace(var.vpc_subnet_cidr) != "" && can(cidrhost(var.vpc_subnet_cidr, 0)))
    error_message = "The vpc_subnet_cidr must be null (to load from SOPS gcp.subnet_cidr) or a valid IPv4 CIDR block."
  }
}

variable "admin_cidr" {
  type        = string
  description = "Optional emergency breakglass IPv4 CIDR block for TCP/22 ingress. Leave null in steady state."
  sensitive   = true
  nullable    = true
  default     = null

  validation {
    condition     = var.admin_cidr == null || var.admin_cidr == "" || can(cidrhost(var.admin_cidr, 0))
    error_message = "When set, admin_cidr must be a valid IPv4 CIDR block (e.g., 203.0.113.10/32)."
  }
}

variable "tailscale_bootstrap_tags" {
  type        = list(string)
  description = "Tailscale tags assigned to the GCP workload identity federation trust for gcp-default-vm."
  default = [
    "tag:type-server",
    "tag:os-linux",
    "tag:hosting-cloud",
    "tag:location-us",
    "tag:env-gcp",
  ]

  validation {
    condition     = length(var.tailscale_bootstrap_tags) > 0 && alltrue([for t in var.tailscale_bootstrap_tags : can(regex("^tag:[a-z0-9-]+$", t))])
    error_message = "tailscale_bootstrap_tags must be non-empty and every entry must match ^tag:[a-z0-9-]+$."
  }
}

variable "secrets_file_path" {
  type        = string
  description = "Path to the canonical SOPS credentials file (defaults to production credentials)."
  default     = "../../secrets/credentials.sops.yaml"

  validation {
    condition     = can(regex("\\.ya?ml$", var.secrets_file_path))
    error_message = "Secrets file path must point to a YAML file (.yaml or .yml)."
  }
}

variable "enable_prevent_destroy" {
  type        = bool
  description = "Whether to prevent destruction of critical compute and backup resources."
  default     = true
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
