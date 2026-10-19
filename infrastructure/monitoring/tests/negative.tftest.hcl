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

run "reject_excessive_healthcheck_timeout" {
  command = plan

  variables {
    healthcheck_timeout = 172800 # 48 hours exceeds 24 hour max limit
  }

  expect_failures = [
    var.healthcheck_timeout,
  ]
}

run "reject_inadequate_healthcheck_grace" {
  command = plan

  variables {
    healthcheck_grace = 60 # 1 minute is under the 300s minimum grace period
  }

  expect_failures = [
    var.healthcheck_grace,
  ]
}

run "reject_underflow_healthcheck_timeout" {
  command = plan

  variables {
    healthcheck_timeout = 30 # Under 60 seconds minimum limit
  }

  expect_failures = [
    var.healthcheck_timeout,
  ]
}

run "reject_excessive_healthcheck_grace" {
  command = plan

  variables {
    healthcheck_grace = 20000 # Exceeds 14400s (4h) maximum limit
  }

  expect_failures = [
    var.healthcheck_grace,
  ]
}

run "reject_short_state_encryption_passphrase" {
  command = plan

  variables {
    state_encryption_passphrase = "too-short-test-passphrase"
  }

  expect_failures = [
    var.state_encryption_passphrase,
  ]
}

run "reject_placeholder_state_encryption_passphrase" {
  command = plan

  variables {
    state_encryption_passphrase = "changeme-changeme-changeme-changeme-0001"
  }

  expect_failures = [
    var.state_encryption_passphrase,
  ]
}

run "reject_missing_homelab_in_default_tags" {
  command = plan

  variables {
    default_tags = ["backup", "restic"]
  }

  expect_failures = [
    var.default_tags,
  ]
}

run "reject_missing_homelab_in_check_tags" {
  command = plan

  variables {
    check_tags = ["backup", "restic"]
  }

  expect_failures = [
    var.check_tags,
  ]
}

run "reject_empty_compose_target_id" {
  command = plan

  variables {
    compose_targets = ["homelab", ""]
  }

  expect_failures = [
    var.compose_targets,
  ]
}

run "reject_duplicate_compose_target_id" {
  command = plan

  variables {
    compose_targets = ["homelab", "gcp", "homelab"]
  }

  expect_failures = [
    var.compose_targets,
  ]
}

run "reject_empty_backup_hosts_list" {
  command = plan

  variables {
    backup_hosts = []
  }

  expect_failures = [
    var.backup_hosts,
  ]
}

run "reject_invalid_backup_host_id" {
  command = plan

  variables {
    backup_hosts = ["oci-amd-1", "Invalid_Host"]
  }

  expect_failures = [
    var.backup_hosts,
  ]
}

run "reject_duplicate_backup_host_id" {
  command = plan

  variables {
    backup_hosts = ["oci-amd-1", "gcp-default-vm", "oci-amd-1"]
  }

  expect_failures = [
    var.backup_hosts,
  ]
}
