mock_provider "healthchecksio" {}

variables {
  healthchecksio_api_key = "mock-healthchecksio-api-key"
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
}
