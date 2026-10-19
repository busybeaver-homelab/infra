mock_provider "github" {}
mock_provider "sops" {}
mock_provider "external" {}

override_data {
  target = data.external.sops_github_config
  values = {
    result = {
      json = <<-EOT
        {
          "repositories": {
            "infra": {
              "name": "infra",
              "description": "Infrastructure as Code for my homelab environment",
              "topics": ["homelab", "infrastructure-as-code", "iac"]
            }
          }
        }
      EOT
    }
  }
}

override_data {
  target = data.external.sops_github_ci_age_key
  values = {
    result = {
      json = "\"\""
    }
  }
}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
  sops_age_key_ci             = format("%s%s", "AGE-SECRET-KEY-1", join("", [for _ in range(58) : "Q"])) # synthetic, format-valid test identity
  github_token                = "mock-ghp-token-12345"
  github_owner                = "mock-owner"
}

run "reject_merge_commit_enabled" {
  command = plan

  variables {
    allow_merge_commit = true
  }

  expect_failures = [
    var.allow_merge_commit,
  ]
}

run "reject_rebase_merge_enabled" {
  command = plan

  variables {
    allow_rebase_merge = true
  }

  expect_failures = [
    var.allow_rebase_merge,
  ]
}

run "reject_keyring_as_ci_age_key" {
  command = plan

  variables {
    sops_age_key_ci = format(
      "%s%s\n%s%s",
      "AGE-SECRET-KEY-1",
      join("", [for _ in range(58) : "Q"]),
      "AGE-SECRET-KEY-1",
      join("", [for _ in range(58) : "Q"]),
    )
  }

  expect_failures = [
    var.sops_age_key_ci,
  ]
}

run "reject_malformed_ci_age_key" {
  command = plan

  variables {
    sops_age_key_ci = "invalid-not-an-age-key"
  }

  expect_failures = [
    var.sops_age_key_ci,
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

run "reject_sops_age_key_ci_in_backup_secrets" {
  command = plan

  variables {
    backup_secrets = {
      SOPS_AGE_KEY_CI = "synthetic-backup-value-0001"
    }
  }

  expect_failures = [
    var.backup_secrets,
  ]
}

run "reject_sops_age_key_ci_in_ops_secrets" {
  command = plan

  variables {
    ops_secrets = {
      SOPS_AGE_KEY_CI = "synthetic-ops-value-0001"
    }
  }

  expect_failures = [
    var.ops_secrets,
  ]
}

run "reject_shared_ci_secret_value_in_backup_secrets" {
  command = plan

  variables {
    ci_secrets = {
      CI_ONLY_TOKEN = "shared-secret-value-0001"
    }
    backup_secrets = {
      BACKUP_TOKEN = "shared-secret-value-0001"
    }
  }

  expect_failures = [
    var.backup_secrets,
  ]
}

run "reject_shared_ci_secret_value_in_ops_secrets" {
  command = plan

  variables {
    ci_secrets = {
      CI_ONLY_TOKEN = "shared-secret-value-0002"
    }
    ops_secrets = {
      OPS_TOKEN = "shared-secret-value-0002"
    }
  }

  expect_failures = [
    var.ops_secrets,
  ]
}

run "reject_writable_deploy_key" {
  command = plan

  variables {
    deploy_keys = {
      "writable-key" = {
        title     = "writable-key"
        key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockKeyForTestingOnly0000000000000000000000"
        read_only = false
      }
    }
  }

  expect_failures = [
    var.deploy_keys,
  ]
}

run "reject_deploy_key_with_email_comment" {
  command = plan

  variables {
    deploy_keys = {
      "email-key" = {
        title     = "email-key"
        key       = format("%s %s%s%s", "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockKeyForTestingOnly0000000000000000000000", "user", "\u0040", "example.test")
        read_only = true
      }
    }
  }

  expect_failures = [
    var.deploy_keys,
  ]
}
