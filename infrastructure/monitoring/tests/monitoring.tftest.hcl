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
    condition     = length(healthchecksio_check.host_backup) == 4
    error_message = "host_backup check map must declare one check per default backup_hosts entry (4 hosts)"
  }

  assert {
    condition = alltrue([
      for h, c in healthchecksio_check.host_backup :
      c.name == "homelab-restic-backup-${h}" &&
      c.timeout == 86400 &&
      c.grace == 7200 &&
      contains(c.tags, "homelab") &&
      contains(c.tags, "backup") &&
      contains(c.tags, "restic") &&
      contains(c.tags, h)
    ])
    error_message = "Each host_backup check must be named homelab-restic-backup-<host> with 86400s timeout, 7200s grace, and homelab/backup/restic/<host> tags"
  }

  assert {
    condition     = length(healthchecksio_check.host_alive) == 4
    error_message = "host_alive check map must declare one check per default backup_hosts entry (4 hosts)"
  }

  assert {
    condition = alltrue([
      for h, c in healthchecksio_check.host_alive :
      c.name == "homelab-host-alive-${h}" &&
      c.timeout == 1800 &&
      c.grace == 900 &&
      contains(c.tags, "homelab") &&
      contains(c.tags, "alive") &&
      contains(c.tags, h)
    ])
    error_message = "Each host_alive check must be named homelab-host-alive-<host> with 1800s timeout, 900s grace, and homelab/alive/<host> tags"
  }

  assert {
    condition = (
      data.healthchecksio_channel.email.kind == "email" &&
      contains(healthchecksio_check.restic_backup.channels, data.healthchecksio_channel.email.id) &&
      contains(healthchecksio_check.drift_detection.channels, data.healthchecksio_channel.email.id) &&
      contains(healthchecksio_check.backup_prune.channels, data.healthchecksio_channel.email.id) &&
      contains(healthchecksio_check.dr_copy.channels, data.healthchecksio_channel.email.id) &&
      contains(healthchecksio_check.ci_schedule.channels, data.healthchecksio_channel.email.id) &&
      contains(healthchecksio_check.codeql_schedule.channels, data.healthchecksio_channel.email.id) &&
      alltrue([for c in healthchecksio_check.compose : contains(c.channels, data.healthchecksio_channel.email.id)]) &&
      alltrue([for c in healthchecksio_check.host_backup : contains(c.channels, data.healthchecksio_channel.email.id)]) &&
      alltrue([for c in healthchecksio_check.host_alive : contains(c.channels, data.healthchecksio_channel.email.id)])
    )
    error_message = "Every Healthchecks.io check must wire data.healthchecksio_channel.email.id in channels (R2-OPS-03)"
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
    condition     = healthchecksio_check.dr_copy.name == "homelab-restic-dr-copy" && healthchecksio_check.dr_copy.timeout == 86400 && healthchecksio_check.dr_copy.grace == 7200 && contains(healthchecksio_check.dr_copy.tags, "homelab") && contains(healthchecksio_check.dr_copy.tags, "dr")
    error_message = "DR copy check must be named homelab-restic-dr-copy with 86400s timeout, 7200s grace, and homelab/dr tags (R2-OPS-02)"
  }

  assert {
    condition     = healthchecksio_check.ci_schedule.name == "homelab-ci-schedule" && healthchecksio_check.ci_schedule.timeout == 604800 && healthchecksio_check.ci_schedule.grace == 7200 && contains(healthchecksio_check.ci_schedule.tags, "homelab")
    error_message = "CI schedule check must be configured with 604800s timeout, 7200s grace, and homelab tag (R2-CI-06)"
  }

  assert {
    condition     = healthchecksio_check.codeql_schedule.name == "homelab-codeql-schedule" && healthchecksio_check.codeql_schedule.timeout == 604800 && healthchecksio_check.codeql_schedule.grace == 7200 && contains(healthchecksio_check.codeql_schedule.tags, "homelab")
    error_message = "CodeQL schedule check must be configured with 604800s timeout, 7200s grace, and homelab tag (R2-CI-06)"
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

run "verify_n_checks_for_n_backup_hosts" {
  command = plan

  variables {
    backup_hosts = ["host-a", "host-b"]
  }

  assert {
    condition     = length(healthchecksio_check.host_backup) == 2 && length(healthchecksio_check.host_alive) == 2
    error_message = "N backup_hosts must produce N host_backup checks and N host_alive checks"
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
    condition = (
      length(output.host_backup_ping_urls) == 4 &&
      alltrue([for k, v in output.host_backup_ping_urls : v != ""])
    )
    error_message = "Per-host backup ping URLs map must be computed on apply for all 4 backup_hosts"
  }

  assert {
    condition = (
      length(output.host_alive_ping_urls) == 4 &&
      alltrue([for k, v in output.host_alive_ping_urls : v != ""])
    )
    error_message = "Per-host alive ping URLs map must be computed on apply for all 4 backup_hosts"
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
    condition     = output.dr_copy_ping_url != ""
    error_message = "DR copy ping URL output must be computed on apply (R2-OPS-02)"
  }

  assert {
    condition     = output.ci_schedule_ping_url != "" && output.codeql_schedule_ping_url != ""
    error_message = "Scheduled CI and CodeQL ping URL outputs must be computed on apply (R2-CI-06)"
  }

  assert {
    condition     = length(output.compose_ping_urls) == 3 && output.compose_ping_urls["homelab"] != "" && output.compose_ping_urls["gcp"] != "" && output.compose_ping_urls["oci-1"] != ""
    error_message = "Per-target compose ping URLs map must be computed on apply"
  }
}
