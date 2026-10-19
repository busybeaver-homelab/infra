data "healthchecksio_channel" "email" {
  kind = "email"
}

resource "healthchecksio_check" "restic_backup" {
  name     = "homelab-restic-backup"
  desc     = "Daily restic backup monitoring for homelab infrastructure"
  timeout  = var.healthcheck_timeout
  grace    = var.healthcheck_grace
  tags     = distinct(concat(var.default_tags, var.check_tags, ["homelab"]))
  channels = [data.healthchecksio_channel.email.id]
}

resource "healthchecksio_check" "host_backup" {
  for_each = toset(nonsensitive(var.backup_hosts))

  name     = "homelab-restic-backup-${each.key}"
  desc     = "Daily Restic backup monitoring for host ${each.key}"
  timeout  = var.healthcheck_timeout
  grace    = var.healthcheck_grace
  tags     = distinct(concat(var.check_tags, ["homelab", "backup", "restic", each.key]))
  channels = [data.healthchecksio_channel.email.id]
}

resource "healthchecksio_check" "host_alive" {
  for_each = toset(nonsensitive(var.backup_hosts))

  name     = "homelab-host-alive-${each.key}"
  desc     = "Host-alive dead-man switch for host ${each.key}"
  timeout  = 1800
  grace    = 900
  tags     = distinct(concat(var.check_tags, ["homelab", "alive", each.key]))
  channels = [data.healthchecksio_channel.email.id]
}

resource "healthchecksio_check" "drift_detection" {
  name     = "homelab-drift-detection"
  desc     = "Daily OpenTofu infrastructure drift detection workflow dead-man switch"
  timeout  = 86400
  grace    = 7200
  tags     = distinct(concat(var.check_tags, ["homelab", "ci", "drift"]))
  channels = [data.healthchecksio_channel.email.id]
}

resource "healthchecksio_check" "backup_prune" {
  name     = "homelab-restic-prune"
  desc     = "Weekly Restic repository prune and integrity check workflow dead-man switch"
  timeout  = 604800
  grace    = 14400
  tags     = distinct(concat(var.check_tags, ["homelab", "ci", "backup", "prune"]))
  channels = [data.healthchecksio_channel.email.id]
}

resource "healthchecksio_check" "ci_schedule" {
  name     = "homelab-ci-schedule"
  desc     = "Weekly scheduled CI workflow dead-man switch"
  timeout  = 604800
  grace    = 7200
  tags     = distinct(concat(var.check_tags, ["homelab", "ci", "schedule"]))
  channels = [data.healthchecksio_channel.email.id]
}

resource "healthchecksio_check" "codeql_schedule" {
  name     = "homelab-codeql-schedule"
  desc     = "Weekly scheduled CodeQL and security scanning workflow dead-man switch"
  timeout  = 604800
  grace    = 7200
  tags     = distinct(concat(var.check_tags, ["homelab", "ci", "codeql", "schedule"]))
  channels = [data.healthchecksio_channel.email.id]
}

resource "healthchecksio_check" "compose" {
  for_each = toset(nonsensitive(var.compose_targets))

  name     = "homelab-compose-${each.key}"
  desc     = "GitOps Docker Compose reconciler and weekly cleanup monitoring (${each.key})"
  timeout  = 900
  grace    = 2700
  tags     = distinct(concat(var.check_tags, ["homelab", "compose", each.key]))
  channels = [data.healthchecksio_channel.email.id]
}

