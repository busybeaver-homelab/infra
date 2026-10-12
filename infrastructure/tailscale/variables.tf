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
  description = "Path to Tailscale ACL HuJSON policy template file."
  default     = "policy.hujson.tftpl"

  validation {
    condition     = endswith(var.policy_file_path, ".hujson.tftpl") || endswith(var.policy_file_path, ".hujson") || endswith(var.policy_file_path, ".json")
    error_message = "The policy file path must have a .hujson.tftpl, .hujson, or .json extension."
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

variable "auth_keys" {
  description = "Map of role-specific authentication keys to manage declaratively."
  type = map(object({
    reusable      = bool
    ephemeral     = bool
    preauthorized = bool
    expiry        = number
    description   = string
    tags          = list(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.auth_keys : alltrue([
        for tag in v.tags : startswith(tag, "tag:")
      ])
    ])
    error_message = "All auth key tags must start with the 'tag:' prefix."
  }
}

variable "infrastructure_devices" {
  description = "Declarative specification of managed infrastructure nodes and their tags."
  type = map(object({
    tags                = list(string)
    key_expiry_disabled = optional(bool, true)
    authorized          = optional(bool, true)
  }))
  default = {
    "adguard-home"   = { tags = ["tag:hosting-onpremise", "tag:svc-adguard", "tag:type-docker"] }
    "beszel"         = { tags = ["tag:hosting-onpremise", "tag:svc-beszel", "tag:type-docker"] }
    "gcp-default-vm" = { tags = ["tag:env-gcp", "tag:hosting-cloud", "tag:location-us", "tag:os-linux", "tag:type-server"] }
    "heide-apple-tv" = { tags = ["tag:hosting-onpremise", "tag:location-ger", "tag:os-appletv"] }
    "node-red"       = { tags = ["tag:hosting-onpremise", "tag:svc-node-red", "tag:type-docker"] }
    "nuc-kvm"        = { tags = ["tag:hosting-onpremise", "tag:location-ger", "tag:os-linux"] }
    "nuc-linux"      = { tags = ["tag:hosting-onpremise", "tag:location-ger", "tag:os-linux", "tag:type-server"] }
    "nuc-windows"    = { tags = ["tag:hosting-onpremise", "tag:location-ger", "tag:os-windows", "tag:type-server"] }
    "synology-nas1"  = { tags = ["tag:hosting-onpremise", "tag:os-linux", "tag:type-nas"] }
    "unifi-gateway"  = { tags = ["tag:hosting-onpremise", "tag:os-linux", "tag:type-network"] }
  }

  validation {
    condition = alltrue([
      for host, dev in var.infrastructure_devices : alltrue([
        for tag in dev.tags : startswith(tag, "tag:")
      ])
    ])
    error_message = "All infrastructure device tags must start with the 'tag:' prefix."
  }
}

variable "device_id_overrides" {
  description = "Optional mapping of hostname to device ID for offline testing without live tailnet API."
  type        = map(string)
  default     = {}
}

variable "device_subnet_routes" {
  description = "Map of hostname to approved subnet routes."
  type        = map(list(string))
  default     = {}

  validation {
    condition = alltrue([
      for host, routes in var.device_subnet_routes : alltrue([
        for r in routes : can(cidrnetmask(r))
      ])
    ])
    error_message = "All subnet routes must be valid IPv4 or IPv6 CIDR blocks."
  }
}




