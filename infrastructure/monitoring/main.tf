resource "healthchecksio_check" "restic_backup" {
  name    = "homelab-restic-backup"
  desc    = "Daily restic backup monitoring for homelab infrastructure"
  timeout = var.healthcheck_timeout
  grace   = var.healthcheck_grace
  tags    = distinct(concat(var.default_tags, var.check_tags, ["homelab"]))
}

resource "healthchecksio_check" "oci_restic_backup" {
  name    = "homelab-oci-restic-backup"
  desc    = "Daily OCI restic backup monitoring"
  timeout = var.healthcheck_timeout
  grace   = var.healthcheck_grace
  tags    = distinct(concat(var.check_tags, ["homelab", "oci", "backup", "restic"]))
}

resource "healthchecksio_check" "gcp_restic_backup" {
  name    = "homelab-gcp-restic-backup"
  desc    = "Daily GCP restic backup monitoring"
  timeout = var.healthcheck_timeout
  grace   = var.healthcheck_grace
  tags    = distinct(concat(var.check_tags, ["homelab", "gcp", "backup", "restic"]))
}

resource "healthchecksio_check" "drift_detection" {
  name    = "homelab-drift-detection"
  desc    = "Daily OpenTofu infrastructure drift detection workflow dead-man switch"
  timeout = 86400
  grace   = 7200
  tags    = distinct(concat(var.check_tags, ["homelab", "ci", "drift"]))
}

resource "healthchecksio_check" "backup_prune" {
  name    = "homelab-restic-prune"
  desc    = "Weekly Restic repository prune and integrity check workflow dead-man switch"
  timeout = 604800
  grace   = 14400
  tags    = distinct(concat(var.check_tags, ["homelab", "ci", "backup", "prune"]))
}
