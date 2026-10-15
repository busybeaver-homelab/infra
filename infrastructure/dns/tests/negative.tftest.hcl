mock_provider "nextdns" {
  alias = "account_1"
}
mock_provider "nextdns" {
  alias = "account_2"
}
mock_provider "nextdns" {
  alias = "account_3"
}
mock_provider "nextdns" {
  alias = "account_4"
}
mock_provider "nextdns" {
  alias = "account_5"
}

mock_provider "sops" {}

mock_provider "external" {
  override_data {
    target = data.external.sops_config
    values = {
      result = {
        json = <<-EOT
          {
            "accounts": {
              "account_1": { "profile_id": "dec001", "profile_name": "p1" },
              "account_2": { "profile_id": "dec002", "profile_name": "p2" },
              "account_3": { "profile_id": "dec003", "profile_name": "p3" },
              "account_4": { "profile_id": "dec004", "profile_name": "p4" },
              "account_5": { "profile_id": "dec005", "profile_name": "p5" }
            },
            "shared": {
              "rewrites": [],
              "allowlist": [],
              "denylist": []
            }
          }
        EOT
      }
    }
  }
}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
}

run "reject_non_yaml_secrets_file_path" {
  command = plan

  variables {
    secrets_file_path = "../../secrets/credentials.json"
  }

  expect_failures = [
    var.secrets_file_path,
  ]
}

run "reject_short_state_encryption_passphrase" {
  command = plan

  variables {
    state_encryption_passphrase = "too-short-passphrase"
  }

  expect_failures = [
    var.state_encryption_passphrase,
  ]
}

run "reject_placeholder_state_encryption_passphrase" {
  command = plan

  variables {
    state_encryption_passphrase = "changeme-changeme-changeme-changeme-1234"
  }

  expect_failures = [
    var.state_encryption_passphrase,
  ]
}
