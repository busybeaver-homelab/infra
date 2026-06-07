variable "cloudflare_api_token" {
  type        = string
  description = "The API token for authenticating with Cloudflare."
  sensitive   = true
}

variable "cloudflare_zone_id" {
  type        = string
  description = "The target DNS zone ID in Cloudflare."
  sensitive   = true
}

