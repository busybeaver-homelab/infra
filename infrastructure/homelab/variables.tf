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

variable "proxmox_insecure" {
  type        = bool
  description = "Whether to bypass TLS certificate verification when connecting to the Proxmox VE API. Must default to false."
  default     = false
}
