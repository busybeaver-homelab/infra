mock_provider "healthchecksio" {
  mock_data "healthchecksio_channel" {
    defaults = {
      id = "00000000-0000-0000-0000-000000000001"
    }
  }
}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
  healthchecksio_api_key      = "mock-healthchecksio-api-key"
}

# STD-OT-54, STD-OT-59: Tagging, channel wiring, and timeout/grace invariants for infrastructure/monitoring.
run "policy_invariants" {
  command = plan

  assert {
    condition = (
      contains(healthchecksio_check.restic_backup.tags, "homelab") &&
      alltrue([for c in healthchecksio_check.host_backup : contains(c.tags, "homelab")]) &&
      alltrue([for c in healthchecksio_check.host_alive : contains(c.tags, "homelab")]) &&
      contains(healthchecksio_check.drift_detection.tags, "homelab") &&
      contains(healthchecksio_check.backup_prune.tags, "homelab") &&
      contains(healthchecksio_check.ci_schedule.tags, "homelab") &&
      contains(healthchecksio_check.codeql_schedule.tags, "homelab") &&
      alltrue([for c in healthchecksio_check.compose : contains(c.tags, "homelab")])
    )
    error_message = "Every Healthchecks.io check must carry the mandatory \"homelab\" tag (STD-OT-37, STD-OT-59)."
  }

  assert {
    condition = (
      healthchecksio_check.restic_backup.grace < healthchecksio_check.restic_backup.timeout &&
      alltrue([for c in healthchecksio_check.host_backup : c.grace < c.timeout]) &&
      alltrue([for c in healthchecksio_check.host_alive : c.grace < c.timeout]) &&
      healthchecksio_check.drift_detection.grace < healthchecksio_check.drift_detection.timeout &&
      healthchecksio_check.backup_prune.grace < healthchecksio_check.backup_prune.timeout &&
      healthchecksio_check.ci_schedule.grace < healthchecksio_check.ci_schedule.timeout &&
      healthchecksio_check.codeql_schedule.grace < healthchecksio_check.codeql_schedule.timeout
    )
    error_message = "Every Healthchecks.io check must configure a grace window strictly smaller than its timeout interval (STD-OT-59)."
  }

  assert {
    condition = (
      length(healthchecksio_check.restic_backup.channels) > 0 &&
      alltrue([for c in healthchecksio_check.host_backup : length(c.channels) > 0]) &&
      alltrue([for c in healthchecksio_check.host_alive : length(c.channels) > 0]) &&
      length(healthchecksio_check.drift_detection.channels) > 0 &&
      length(healthchecksio_check.backup_prune.channels) > 0 &&
      length(healthchecksio_check.ci_schedule.channels) > 0 &&
      length(healthchecksio_check.codeql_schedule.channels) > 0 &&
      alltrue([for c in healthchecksio_check.compose : length(c.channels) > 0])
    )
    error_message = "Every Healthchecks.io check must wire at least one delivery channel (STD-OT-54, R2-OPS-03)."
  }
}
