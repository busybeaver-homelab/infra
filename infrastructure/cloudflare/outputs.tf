output "r2_access_key_id" {
  value       = cloudflare_api_token.r2_state_token.id
  description = "The Access Key ID for Cloudflare R2 remote state backend authentication."
  sensitive   = true
}

output "r2_secret_access_key" {
  value       = sha256(cloudflare_api_token.r2_state_token.value)
  description = "The Secret Access Key (SHA-256 hash of API token) for Cloudflare R2 remote state backend authentication."
  sensitive   = true
}

output "r2_bucket_name" {
  value       = cloudflare_r2_bucket.tfstate.name
  description = "The name of the OpenTofu state storage R2 bucket."
  sensitive   = true
}

output "r2_backup_bucket_name" {
  value       = cloudflare_r2_bucket.backups_dr.name
  description = "The name of the secondary R2 disaster recovery backup bucket."
  sensitive   = true
}

output "r2_backup_endpoint" {
  value       = "https://${var.cloudflare_account_id}.eu.r2.cloudflarestorage.com"
  description = "S3-compatible endpoint URL for the EU jurisdictional R2 backup bucket."
  sensitive   = true
}
