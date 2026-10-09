variable "cloudflare_api_token" {
  type        = string
  description = "The API token for authenticating with Cloudflare."
  sensitive   = true
}

variable "cloudflare_account_id" {
  type        = string
  description = "The Cloudflare account ID for managing R2 and account-level resources."
  sensitive   = true
}

variable "secrets_file_path" {
  type        = string
  description = "Path to the canonical SOPS credentials file holding cloudflare.config (defaults to production credentials)."
  default     = "../../secrets/credentials.sops.yaml"
}
