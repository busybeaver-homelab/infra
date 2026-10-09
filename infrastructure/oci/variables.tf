variable "tenancy_ocid" {
  type        = string
  description = "OCID of the OCI tenancy."
  sensitive   = true

  validation {
    condition     = can(regex("^ocid1\\.tenancy\\.oc1\\..*", var.tenancy_ocid))
    error_message = "The tenancy_ocid must be a valid OCI tenancy OCID starting with 'ocid1.tenancy.oc1..'."
  }
}

variable "user_ocid" {
  type        = string
  description = "OCID of the OCI user for authentication."
  sensitive   = true

  validation {
    condition     = can(regex("^ocid1\\.user\\.oc1\\..*", var.user_ocid))
    error_message = "The user_ocid must be a valid OCI user OCID starting with 'ocid1.user.oc1..'."
  }
}

variable "fingerprint" {
  type        = string
  description = "Fingerprint of the OCI API key."
  sensitive   = true

  validation {
    condition     = can(regex("^([0-9a-fA-F]{2}:){15}[0-9a-fA-F]{2}$", var.fingerprint))
    error_message = "The fingerprint must be a valid 16-octet hex MD5 fingerprint separated by colons."
  }
}

variable "private_key" {
  type        = string
  description = "PEM-encoded private key for OCI API authentication."
  sensitive   = true
}

variable "region" {
  type        = string
  description = "OCI region (e.g., eu-frankfurt-1)."
  sensitive   = true
  default     = "eu-frankfurt-1"
}

variable "compartment_ocid" {
  type        = string
  description = "OCID of the OCI compartment to deploy resources into."
  sensitive   = true

  validation {
    condition     = can(regex("^ocid1\\.(compartment|tenancy)\\.oc1\\..*", var.compartment_ocid))
    error_message = "The compartment_ocid must be a valid OCI compartment or tenancy OCID starting with 'ocid1.compartment.oc1..' or 'ocid1.tenancy.oc1..'."
  }
}

variable "availability_domain" {
  type        = string
  description = "Availability domain for compute instances."
  sensitive   = true
  default     = ""
}

variable "instance_image_ocid_amd" {
  type        = string
  description = "OCID of the Ubuntu Minimal OS image for AMD64 instances."
  sensitive   = true
  default     = ""
}

variable "instance_image_ocid_arm" {
  type        = string
  description = "OCID of the Ubuntu Minimal OS image for ARM64 (Ampere) instances."
  sensitive   = true
  default     = ""
}



variable "budget_amount" {
  type        = number
  description = "Monthly spending limit in USD for the OCI budget (set to 1 for zero-spend monitoring)."
  default     = 1
}

variable "budget_alert_threshold" {
  type        = number
  description = "Percentage threshold of the budget amount to trigger alert notification."
  default     = 100
}

variable "forecast_budget_alert_threshold" {
  type        = number
  description = "Percentage threshold of forecasted spending to trigger an early warning alert."
  default     = 100
}

variable "budget_alert_recipients" {
  type        = string
  description = "Email address(es) to receive budget alert notifications (comma-separated)."
  sensitive   = true
  default     = "admin@example.com"
}

variable "vcn_cidr" {
  type        = string
  description = "IPv4 CIDR block for the Virtual Cloud Network (VCN)."
  sensitive   = true
}

variable "subnet_cidr" {
  type        = string
  description = "IPv4 CIDR block for the private compute subnet."
  sensitive   = true
}

variable "tailscale_auth_key" {
  type        = string
  description = "Tailscale authentication key for instance bootstrapping."
  sensitive   = true
  default     = ""
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for emergency access to compute instances."
  sensitive   = true
  default     = ""
}

variable "admin_cidr" {
  type        = string
  description = "IPv4 CIDR block authorized for emergency SSH access (e.g. bastion, management subnet, or CGNAT)."
  sensitive   = true
  default     = ""
}

variable "tenancy_name" {
  type        = string
  description = "Name of the tenancy used for prefixing globally unique resources like object storage buckets."
  sensitive   = true
  default     = "homelab"
}

variable "tailscale_common_tags" {
  type        = list(string)
  description = "Common Tailscale tags applied across all cloud instances."
  default     = ["tag:type-server", "tag:os-linux", "tag:hosting-cloud"]
}

variable "tailscale_extra_tags_oci" {
  type        = list(string)
  description = "OCI-specific Tailscale tags applied to OCI compute instances."
  default     = ["tag:location-ger", "tag:env-oci"]
}

variable "default_freeform_tags" {
  type        = map(string)
  description = "Default freeform tags applied to all OCI resources."
  default = {
    "project" = "homelab"
  }

  validation {
    condition     = !contains(keys(var.default_freeform_tags), "project") || lookup(var.default_freeform_tags, "project", "") == "homelab"
    error_message = "If the 'project' tag is defined in default_freeform_tags, it must be 'homelab'."
  }
}

variable "assign_public_ip" {
  type        = bool
  description = "Whether to assign a public IP to compute instance VNICs (must be false in Always Free homelab architecture)."
  default     = false

  validation {
    condition     = var.assign_public_ip == false
    error_message = "assign_public_ip must be false. Public IP assignment is prohibited."
  }
}

variable "ampere_ocpus" {
  type        = number
  description = "Number of OCPUs for the Ampere ARM compute instance (must not exceed 4 for Always Free Tier)."
  default     = 4

  validation {
    condition     = var.ampere_ocpus >= 1 && var.ampere_ocpus <= 4
    error_message = "ampere_ocpus must be between 1 and 4 to remain within the OCI Always Free Tier limits."
  }
}

variable "ampere_memory_in_gbs" {
  type        = number
  description = "Memory in GBs for the Ampere ARM compute instance (must not exceed 24 for Always Free Tier)."
  default     = 24

  validation {
    condition     = var.ampere_memory_in_gbs >= 1 && var.ampere_memory_in_gbs <= 24
    error_message = "ampere_memory_in_gbs must be between 1 and 24 to remain within the OCI Always Free Tier limits."
  }
}

variable "secrets_file_path" {
  type        = string
  description = "Path to the canonical SOPS credentials file (defaults to production credentials)."
  default     = "../../secrets/credentials.sops.yaml"
}

