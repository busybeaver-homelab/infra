variable "tenancy_ocid" {
  type        = string
  description = "OCID of the OCI tenancy."
  sensitive   = true
}

variable "user_ocid" {
  type        = string
  description = "OCID of the OCI user for authentication."
  sensitive   = true
}

variable "fingerprint" {
  type        = string
  description = "Fingerprint of the OCI API key."
  sensitive   = true
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
}

# Compute variables (enabled in Task 7)
# variable "availability_domain" { ... }
# variable "instance_image_ocid_amd" { ... }
# variable "instance_image_ocid_arm" { ... }

variable "state_encryption_passphrase" {
  type        = string
  description = "Passphrase for OpenTofu state encryption (AES-GCM via PBKDF2). Never hardcode — inject via TF_VAR_state_encryption_passphrase environment variable."
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
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  type        = string
  description = "IPv4 CIDR block for the private compute subnet."
  sensitive   = true
  default     = "10.0.1.0/24"
}

# Compute bootstrap variables (enabled in Task 7)
# variable "tailscale_auth_key" { ... }
# variable "ssh_public_key" { ... }
