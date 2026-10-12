variable "secrets_file_path" {
  type        = string
  description = "Path to the canonical SOPS credentials file holding tailscale credentials."
  default     = "../../secrets/credentials.sops.yaml"
}

variable "policy_file_path" {
  type        = string
  description = "Path to Tailscale ACL HuJSON policy file."
  default     = "policy.hujson"
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
}
