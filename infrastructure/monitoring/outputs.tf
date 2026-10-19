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

output "host_backup_ping_urls" {
  value       = { for k, v in healthchecksio_check.host_backup : k => v.ping_url }
  description = "Map of inventory hostnames to their unique Restic backup Healthchecks.io ping URLs."
  sensitive   = true
}

output "host_alive_ping_urls" {
  value       = { for k, v in healthchecksio_check.host_alive : k => v.ping_url }
  description = "Map of inventory hostnames to their unique host-alive Healthchecks.io ping URLs."
  sensitive   = true
}

output "drift_detection_ping_url" {
  value       = healthchecksio_check.drift_detection.ping_url
  description = "Unique ping URL for daily OpenTofu drift detection dead-man switch."
  sensitive   = true
}

output "backup_prune_ping_url" {
  value       = healthchecksio_check.backup_prune.ping_url
  description = "Unique ping URL for weekly Restic repository prune and integrity check dead-man switch."
  sensitive   = true
}

output "dr_copy_ping_url" {
  value       = healthchecksio_check.dr_copy.ping_url
  description = "Unique ping URL for daily Restic pull-model DR copy workflow dead-man switch."
  sensitive   = true
}

output "ci_schedule_ping_url" {
  value       = healthchecksio_check.ci_schedule.ping_url
  description = "Unique ping URL for weekly scheduled CI workflow dead-man switch."
  sensitive   = true
}

output "codeql_schedule_ping_url" {
  value       = healthchecksio_check.codeql_schedule.ping_url
  description = "Unique ping URL for weekly scheduled CodeQL workflow dead-man switch."
  sensitive   = true
}

output "compose_ping_urls" {
  value       = { for k, v in healthchecksio_check.compose : k => v.ping_url }
  description = "Map of logical compose target IDs to their unique Healthchecks.io ping URLs."
  sensitive   = true
}
