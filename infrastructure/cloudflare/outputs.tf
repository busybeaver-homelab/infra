output "root_record_hostname" {
  value       = cloudflare_record.root_record.hostname
  description = "The fully qualified domain name of the root record."
  sensitive   = true
}
