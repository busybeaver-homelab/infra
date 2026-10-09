output "zone_id" {
  value       = cloudflare_zone.this.id
  description = "Cloudflare zone ID."
  sensitive   = true
}

output "effective_settings" {
  value       = local.zone_settings
  description = "Effective zone-setting posture (defaults merged with overrides). Non-identifying."
}
