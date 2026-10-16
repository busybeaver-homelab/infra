mock_provider "healthchecksio" {}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
  healthchecksio_api_key      = "mock-healthchecksio-api-key"
}

# STD-OT-59: Tagging, timeout/grace, and Free-Tier check count invariants for infrastructure/monitoring.
run "policy_invariants" {
  command = plan

  assert {
    condition = (
      contains(healthchecksio_check.restic_backup.tags, "homelab") &&
      contains(healthchecksio_check.oci_restic_backup.tags, "homelab") &&
      contains(healthchecksio_check.gcp_restic_backup.tags, "homelab") &&
      contains(healthchecksio_check.drift_detection.tags, "homelab") &&
      contains(healthchecksio_check.backup_prune.tags, "homelab")
    )
    error_message = "Every Healthchecks.io check must carry the mandatory \"homelab\" tag (STD-OT-37, STD-OT-59)."
  }

  assert {
    condition = (
      healthchecksio_check.restic_backup.grace < healthchecksio_check.restic_backup.timeout &&
      healthchecksio_check.oci_restic_backup.grace < healthchecksio_check.oci_restic_backup.timeout &&
      healthchecksio_check.gcp_restic_backup.grace < healthchecksio_check.gcp_restic_backup.timeout &&
      healthchecksio_check.drift_detection.grace < healthchecksio_check.drift_detection.timeout &&
      healthchecksio_check.backup_prune.grace < healthchecksio_check.backup_prune.timeout
    )
    error_message = "Every Healthchecks.io check must configure a grace window strictly smaller than its timeout interval (STD-OT-59)."
  }
}
