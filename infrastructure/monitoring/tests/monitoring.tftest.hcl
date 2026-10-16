mock_provider "healthchecksio" {}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
  healthchecksio_api_key      = "mock-healthchecksio-api-key"
}

run "verify_healthchecks_check" {
  command = plan

  assert {
    condition     = healthchecksio_check.restic_backup.name == "homelab-restic-backup"
    error_message = "Check name must be homelab-restic-backup"
  }

  assert {
    condition     = healthchecksio_check.restic_backup.timeout == 86400
    error_message = "Check timeout must be 86400 seconds (24h)"
  }

  assert {
    condition     = healthchecksio_check.restic_backup.grace == 7200
    error_message = "Check grace period must be 7200 seconds (2h)"
  }

  assert {
    condition     = contains(healthchecksio_check.restic_backup.tags, "homelab")
    error_message = "Check must include homelab tag"
  }

  assert {
    condition     = healthchecksio_check.oci_restic_backup.name == "homelab-oci-restic-backup" && contains(healthchecksio_check.oci_restic_backup.tags, "homelab") && contains(healthchecksio_check.oci_restic_backup.tags, "oci")
    error_message = "OCI restic backup check must be configured with homelab and oci tags"
  }

  assert {
    condition     = healthchecksio_check.gcp_restic_backup.name == "homelab-gcp-restic-backup" && contains(healthchecksio_check.gcp_restic_backup.tags, "homelab") && contains(healthchecksio_check.gcp_restic_backup.tags, "gcp")
    error_message = "GCP restic backup check must be configured with homelab and gcp tags"
  }

  assert {
    condition     = healthchecksio_check.drift_detection.name == "homelab-drift-detection" && healthchecksio_check.drift_detection.timeout == 86400 && healthchecksio_check.drift_detection.grace == 7200 && contains(healthchecksio_check.drift_detection.tags, "homelab")
    error_message = "Drift detection check must be configured with 86400s timeout, 7200s grace, and homelab tag"
  }

  assert {
    condition     = healthchecksio_check.backup_prune.name == "homelab-restic-prune" && healthchecksio_check.backup_prune.timeout == 604800 && healthchecksio_check.backup_prune.grace == 14400 && contains(healthchecksio_check.backup_prune.tags, "homelab")
    error_message = "Backup prune check must be configured with 604800s timeout, 14400s grace, and homelab tag"
  }

  assert {
    condition     = length(healthchecksio_check.compose) == 3
    error_message = "Compose check map must declare one check per default compose_targets entry"
  }

  assert {
    condition     = healthchecksio_check.compose["homelab"].name == "homelab-compose-homelab" && healthchecksio_check.compose["homelab"].timeout == 900 && healthchecksio_check.compose["homelab"].grace == 2700 && contains(healthchecksio_check.compose["homelab"].tags, "homelab") && contains(healthchecksio_check.compose["homelab"].tags, "compose")
    error_message = "Homelab compose check must be named homelab-compose-homelab with 900s timeout, 2700s grace, and homelab/compose tags"
  }

  assert {
    condition     = healthchecksio_check.compose["gcp"].name == "homelab-compose-gcp" && healthchecksio_check.compose["gcp"].timeout == 900 && healthchecksio_check.compose["gcp"].grace == 2700 && contains(healthchecksio_check.compose["gcp"].tags, "homelab") && contains(healthchecksio_check.compose["gcp"].tags, "compose")
    error_message = "GCP compose check must be named homelab-compose-gcp with 900s timeout, 2700s grace, and homelab/compose tags"
  }

  assert {
    condition     = healthchecksio_check.compose["oci-1"].name == "homelab-compose-oci-1" && healthchecksio_check.compose["oci-1"].timeout == 900 && healthchecksio_check.compose["oci-1"].grace == 2700 && contains(healthchecksio_check.compose["oci-1"].tags, "homelab") && contains(healthchecksio_check.compose["oci-1"].tags, "compose")
    error_message = "OCI-1 compose check must be named homelab-compose-oci-1 with 900s timeout, 2700s grace, and homelab/compose tags"
  }
}

run "verify_computed_outputs_on_apply" {
  command = apply

  assert {
    condition     = output.restic_backup_ping_url != ""
    error_message = "Healthchecks.io ping URL output must be computed on apply"
  }

  assert {
    condition     = output.restic_backup_check_id != ""
    error_message = "Healthchecks.io check ID output must be computed on apply"
  }

  assert {
    condition     = output.oci_restic_ping_url != ""
    error_message = "OCI restic ping URL output must be computed on apply"
  }

  assert {
    condition     = output.gcp_restic_ping_url != ""
    error_message = "GCP restic ping URL output must be computed on apply"
  }

  assert {
    condition     = output.drift_detection_ping_url != ""
    error_message = "Drift detection ping URL output must be computed on apply"
  }

  assert {
    condition     = output.backup_prune_ping_url != ""
    error_message = "Backup prune ping URL output must be computed on apply"
  }

  assert {
    condition     = length(output.compose_ping_urls) == 3 && output.compose_ping_urls["homelab"] != "" && output.compose_ping_urls["gcp"] != "" && output.compose_ping_urls["oci-1"] != ""
    error_message = "Per-target compose ping URLs map must be computed on apply"
  }
}
