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
