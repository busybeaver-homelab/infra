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
  github_token = "mock-ghp-token-12345"
  github_owner = "mock-owner"
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
