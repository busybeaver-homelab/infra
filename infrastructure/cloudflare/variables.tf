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

variable "r2_backup_bucket_name" {
  type        = string
  description = "The name of the Cloudflare R2 bucket for disaster recovery backups."
  default     = "homelab-backups-dr"

  validation {
    condition     = can(regex("^homelab-[a-z0-9][a-z0-9-]{1,55}[a-z0-9]$", var.r2_backup_bucket_name))
    error_message = "r2_backup_bucket_name must start with 'homelab-', contain only lowercase alphanumeric characters and hyphens, and conform to RFC 1123 naming rules."
  }
}

variable "r2_backup_location" {
  type        = string
  description = "Location hint for the R2 disaster recovery backup bucket."
  default     = "weur"

  validation {
    condition     = contains(["weur", "eeur", "apac", "enam", "wnam", "oc"], var.r2_backup_location)
    error_message = "r2_backup_location must be one of: weur, eeur, apac, enam, wnam, oc."
  }
}

variable "enable_prevent_destroy" {
  type        = bool
  description = "Whether to prevent destruction of critical Cloudflare resources (defaults to true for production safety)."
  default     = true
}
