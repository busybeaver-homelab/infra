resource "healthchecksio_check" "restic_backup" {
  name    = "homelab-restic-backup"
  desc    = "Daily restic backup monitoring for homelab infrastructure"
  timeout = var.healthcheck_timeout
  grace   = var.healthcheck_grace
  tags    = var.default_tags
}
