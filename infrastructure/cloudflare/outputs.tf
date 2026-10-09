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
