mock_provider "github" {}

mock_provider "sops" {
  override_data {
    target = data.sops_file.secrets
    values = {
      raw = <<-EOT
        github:
          owner: "mock-owner"
          token: "mock-ghp-token-12345"
          config:
            repositories:
              infra:
                name: "infra"
                description: "Infrastructure as Code for my homelab environment"
                topics:
                  - "homelab"
                  - "infrastructure-as-code"
                  - "iac"
        opentofu:
          state_encryption_passphrase: "mock-passphrase"
      EOT
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
    sops_age_key_ci = format("%s\n%s", var.sops_age_key_ci, var.sops_age_key_ci)
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
