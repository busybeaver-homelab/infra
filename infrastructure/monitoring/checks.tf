check "enforce_healthcheck_cadence_and_tags" {
  assert {
    condition = (
      healthchecksio_check.restic_backup.timeout <= 86400 &&
      healthchecksio_check.oci_restic_backup.timeout <= 86400 &&
      healthchecksio_check.gcp_restic_backup.timeout <= 86400 &&
      healthchecksio_check.drift_detection.timeout == 86400 &&
      healthchecksio_check.backup_prune.timeout == 604800 &&
      alltrue([for c in healthchecksio_check.compose : c.timeout == 900 && c.grace == 2700])
    )
    error_message = "Healthcheck timeouts must adhere to 15m compose (900s), daily (<=86400s), or weekly (604800s) cadence requirements"
  }

  assert {
    condition = (
      contains(healthchecksio_check.restic_backup.tags, "homelab") &&
      contains(healthchecksio_check.oci_restic_backup.tags, "homelab") &&
      contains(healthchecksio_check.gcp_restic_backup.tags, "homelab") &&
      contains(healthchecksio_check.drift_detection.tags, "homelab") &&
      contains(healthchecksio_check.backup_prune.tags, "homelab") &&
      alltrue([for c in healthchecksio_check.compose : contains(c.tags, "homelab") && contains(c.tags, "compose")])
    )
    error_message = "Mandatory tag 'homelab' must be present on all healthchecks"
  }
}
