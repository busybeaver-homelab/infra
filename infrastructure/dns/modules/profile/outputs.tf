output "profile_id" {
  description = "The 6-character NextDNS profile ID."
  value       = nextdns_profile.this.id
  sensitive   = true
}

output "rewrite_enabled" {
  description = "Whether the nextdns_rewrite resource is instantiated for this profile."
  value       = length(nextdns_rewrite.this) > 0
}

output "allowlist_enabled" {
  description = "Whether the nextdns_allowlist resource is instantiated for this profile."
  value       = length(nextdns_allowlist.this) > 0
}

output "denylist_enabled" {
  description = "Whether the nextdns_denylist resource is instantiated for this profile."
  value       = length(nextdns_denylist.this) > 0
}
