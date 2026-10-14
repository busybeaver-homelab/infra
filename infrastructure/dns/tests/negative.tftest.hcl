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

mock_provider "sops" {
  override_data {
    target = data.sops_file.secrets
    values = {
      raw = <<-EOT
        nextdns:
          accounts:
            account_1: { api_key: "k1" }
            account_2: { api_key: "k2" }
            account_3: { api_key: "k3" }
            account_4: { api_key: "k4" }
          config:
            accounts:
              account_1: { account_name: "A1", profile_id: "dec001", profile_name: "p1" }
              account_2: { account_name: "A2", profile_id: "dec002", profile_name: "p2" }
              account_3: { account_name: "A3", profile_id: "dec003", profile_name: "p3" }
              account_4: { account_name: "A4", profile_id: "dec004", profile_name: "p4" }
            shared:
              rewrites: []
              allowlist: []
              denylist: []
      EOT
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
