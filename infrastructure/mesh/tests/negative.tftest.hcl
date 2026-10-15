mock_provider "tailscale" {}
mock_provider "sops" {}

mock_provider "external" {
  override_data {
    target = data.external.sops_config
    values = {
      result = {
        json = <<-EOT
          {
            "tailnet_name": "example.ts.net",
            "contact_account_email": "account@example.test",
            "contact_support_email": "support@example.test",
            "contact_security_email": "security@example.test"
          }
        EOT
      }
    }
  }
}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
  policy_file_path            = "policy.ci.hujson.tftpl"
}

run "reject_invalid_policy_file_extension" {
  command = plan

  variables {
    policy_file_path = "policy.txt"
  }

  expect_failures = [
    var.policy_file_path,
  ]
}

run "reject_empty_bootstrap_key_tags" {
  command = plan

  variables {
    bootstrap_key_tags = []
  }

  expect_failures = [
    var.bootstrap_key_tags,
  ]
}

run "reject_malformed_bootstrap_key_tag" {
  command = plan

  variables {
    bootstrap_key_tags = ["invalid-tag-no-prefix"]
  }

  expect_failures = [
    var.bootstrap_key_tags,
  ]
}

run "reject_empty_bootstrap_gcp_key_tags" {
  command = plan

  variables {
    bootstrap_gcp_key_tags = []
  }

  expect_failures = [
    var.bootstrap_gcp_key_tags,
  ]
}

run "reject_malformed_bootstrap_gcp_key_tag" {
  command = plan

  variables {
    bootstrap_gcp_key_tags = ["invalid-tag-no-prefix"]
  }

  expect_failures = [
    var.bootstrap_gcp_key_tags,
  ]
}

run "reject_invalid_secrets_file_extension" {
  command = plan

  variables {
    secrets_file_path = "secrets/credentials.json"
  }

  expect_failures = [
    var.secrets_file_path,
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

run "reject_too_short_bootstrap_key_expiry" {
  command = plan

  variables {
    bootstrap_key_expiry = 30
  }

  expect_failures = [
    var.bootstrap_key_expiry,
  ]
}

run "reject_too_long_bootstrap_key_expiry" {
  command = plan

  variables {
    bootstrap_key_expiry = 172800
  }

  expect_failures = [
    var.bootstrap_key_expiry,
  ]
}
