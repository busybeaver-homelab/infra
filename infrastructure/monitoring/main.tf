resource "healthchecksio_check" "restic_backup" {
  name    = "homelab-restic-backup"
  desc    = "Daily restic backup monitoring for homelab infrastructure"
  timeout = 86400
  grace   = 7200
  tags    = var.default_tags
}
