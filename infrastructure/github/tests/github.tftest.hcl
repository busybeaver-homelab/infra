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

run "verify_github_root_hardening" {
  command = plan

  assert {
    condition     = module.repository["infra"].repository_name == "infra"
    error_message = "Repository name must match infra"
  }

  assert {
    condition     = module.repository["infra"].allow_squash_merge == true
    error_message = "Repository must allow squash merge"
  }

  assert {
    condition     = module.repository["infra"].allow_merge_commit == false
    error_message = "Repository must disallow merge commits"
  }

  assert {
    condition     = module.repository["infra"].allow_rebase_merge == false
    error_message = "Repository must disallow rebase commits"
  }

  assert {
    condition     = module.repository["infra"].delete_branch_on_merge == true
    error_message = "Repository must delete head branch on merge"
  }

  assert {
    condition     = module.repository["infra"].ruleset_enforcement == "active"
    error_message = "Main branch ruleset must be actively enforced"
  }

  assert {
    condition     = module.repository["infra"].environments.ci == "ci"
    error_message = "CI environment must be defined"
  }

  assert {
    condition     = module.repository["infra"].environments.backup == "backup"
    error_message = "Backup environment must be defined"
  }
}
