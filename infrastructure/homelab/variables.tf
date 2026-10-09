variable "proxmox_api_endpoint" {
  type        = string
  description = "The HTTPS API endpoint of the Proxmox VE server."
  sensitive   = true

  validation {
    condition     = startswith(var.proxmox_api_endpoint, "https://")
    error_message = "The proxmox_api_endpoint must use HTTPS to protect authentication credentials in transit."
  }
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

  validation {
    condition     = var.proxmox_insecure == false
    error_message = "proxmox_insecure must be false to enforce TLS verification against the Proxmox VE API."
  }
}
