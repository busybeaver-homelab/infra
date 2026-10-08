output "restic_backup_ping_url" {
  value       = healthchecksio_check.restic_backup.ping_url
  description = "Unique ping URL for homelab restic backup completion signal."
  sensitive   = true
}

output "restic_backup_check_id" {
  value       = healthchecksio_check.restic_backup.id
  description = "Unique UUID of the homelab restic backup check."
  sensitive   = true
}
