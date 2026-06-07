variable "proxmox_api_endpoint" {
  type        = string
  description = "The HTTPS API endpoint of the Proxmox VE server."
  sensitive   = true
}

variable "proxmox_api_token" {
  type        = string
  description = "The Proxmox API token (username@realm!tokenid=secret)."
  sensitive   = true
}

variable "state_encryption_passphrase" {
  type        = string
  description = "Passphrase for OpenTofu state encryption (AES-GCM via PBKDF2). Never hardcode — inject via TF_VAR_state_encryption_passphrase environment variable."
  sensitive   = true
}
