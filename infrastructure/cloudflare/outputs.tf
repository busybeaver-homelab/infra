output "root_record_hostname" {
  value       = cloudflare_record.root_record.hostname
  description = "The fully qualified domain name of the root record."
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
