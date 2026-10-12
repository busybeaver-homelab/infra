variable "secrets_file_path" {
  type        = string
  description = "Path to the canonical SOPS credentials file holding tailscale credentials."
  default     = "../../secrets/credentials.sops.yaml"

  validation {
    condition     = can(regex("\\.ya?ml$", var.secrets_file_path))
    error_message = "Secrets file path must point to a YAML file (.yaml or .yml)."
  }
}

variable "policy_file_path" {
  type        = string
  description = "Path to Tailscale ACL HuJSON policy file."
  default     = "policy.hujson"

  validation {
    condition     = endswith(var.policy_file_path, ".hujson") || endswith(var.policy_file_path, ".json")
    error_message = "The policy file path must have a .hujson or .json extension."
  }
}

variable "tailscale_client_id" {
  type        = string
  description = "Tailscale OAuth client ID (overrides SOPS if provided)."
  sensitive   = true
  default     = ""
}

variable "tailscale_client_secret" {
  type        = string
  description = "Tailscale OAuth client secret (overrides SOPS if provided)."
  sensitive   = true
  default     = ""
}

variable "tailnet_name" {
  type        = string
  description = "Tailscale tailnet name (overrides SOPS if provided)."
  default     = ""
}

variable "bootstrap_key_tags" {
  type        = list(string)
  description = "Tailscale tags assigned to the bootstrap authentication key."
  default = [
    "tag:type-server",
    "tag:os-linux",
    "tag:hosting-cloud",
    "tag:location-ger",
    "tag:env-oci",
  ]

  validation {
    condition     = length(var.bootstrap_key_tags) > 0 && alltrue([for t in var.bootstrap_key_tags : can(regex("^tag:[a-z0-9-]+$", t))])
    error_message = "All bootstrap key tags must start with 'tag:' and contain only lowercase alphanumeric characters and hyphens."
  }
}

variable "monitored_device_hostnames" {
  description = "List of device hostnames (without domain suffix) to retrieve via data.tailscale_device."
  type        = list(string)
  default     = ["unifi-gateway", "adguard-home"]
}

variable "dns_nameservers" {
  description = "List of global DNS nameservers for the tailnet."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for ns in var.dns_nameservers : can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$|^[0-9a-fA-F:]+$", ns))])
    error_message = "All DNS nameservers must be valid IPv4 or IPv6 addresses."
  }
}

variable "dns_search_paths" {
  description = "List of search domains for MagicDNS."
  type        = list(string)
  default     = []
}

variable "dns_split_nameservers" {
  description = "Map of domain routes to dedicated split DNS nameservers."
  type        = map(list(string))
  default     = {}

  validation {
    condition = alltrue([
      for domain, servers in var.dns_split_nameservers :
      alltrue([for ns in servers : can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$|^[0-9a-fA-F:]+$", ns))])
    ])
    error_message = "All split DNS nameservers must be valid IPv4 or IPv6 addresses."
  }
}


