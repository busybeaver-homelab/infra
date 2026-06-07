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
  description = "OCI region (e.g., us-ashburn-1)."
  sensitive   = true
}

variable "compartment_ocid" {
  type        = string
  description = "OCID of the OCI compartment to deploy resources into."
  sensitive   = true
}

variable "availability_domain" {
  type        = string
  description = "Availability domain for compute instances."
  sensitive   = true
}

variable "instance_image_ocid" {
  type        = string
  description = "OCID of the OS image to use for compute instances (Ubuntu 22.04 recommended)."
  sensitive   = true
}

variable "instance_shape" {
  type        = string
  description = "OCI compute shape (e.g., VM.Standard.A1.Flex for Always Free ARM)."
  default     = "VM.Standard.A1.Flex"
}

variable "state_encryption_passphrase" {
  type        = string
  description = "Passphrase for OpenTofu state encryption (AES-GCM via PBKDF2). Never hardcode — inject via TF_VAR_state_encryption_passphrase environment variable."
  sensitive   = true
}
