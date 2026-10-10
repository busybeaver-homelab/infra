check "enforce_healthcheck_cadence_and_tags" {
  assert {
    condition     = healthchecksio_check.restic_backup.timeout <= 86400
    error_message = "Daily backup check timeout must not exceed 86400 seconds (24h)"
  }

  assert {
    condition     = contains(healthchecksio_check.restic_backup.tags, "homelab")
    error_message = "Mandatory tag 'homelab' must be present on restic backup healthcheck"
  }
}
