output "r2_tfstate_bucket_name" {
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
  value       = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"
  description = "S3-compatible endpoint URL for the R2 backup bucket."
  sensitive   = true
}

output "r2_restic_prune_s3_access_key_id" {
  value       = cloudflare_api_token.r2_restic_prune.id
  description = "S3 Access Key ID for the dedicated R2 Restic prune/check API token."
  sensitive   = true
}

output "r2_restic_prune_s3_secret_access_key" {
  value       = sha256(cloudflare_api_token.r2_restic_prune.value)
  description = "S3 Secret Access Key (SHA-256 of the API token secret) for the dedicated R2 Restic prune/check API token."
  sensitive   = true
}

output "managed_zone_keys" {
  value       = local.zone_keys
  description = "Logical keys of the zones managed by this module."
  sensitive   = true
}

output "zone_ids" {
  value       = { for k, m in module.zone : k => m.zone_id }
  description = "Cloudflare zone IDs keyed by logical zone key."
  sensitive   = true
}
