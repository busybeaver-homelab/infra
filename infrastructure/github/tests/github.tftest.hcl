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
    condition     = module.repository["infra"].visibility == "public"
    error_message = "Repository visibility must be public"
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

  assert {
    condition     = module.repository["infra"].environments.code_quality == "code_quality"
    error_message = "Code quality environment must be defined in outputs"
  }

  assert {
    condition     = module.repository["infra"].actions_permissions.allowed_actions == "selected"
    error_message = "Actions permissions must be selected"
  }

  assert {
    condition     = module.repository["infra"].actions_permissions.sha_pinning_required == true
    error_message = "Actions must require SHA pinning"
  }

  assert {
    condition     = contains(keys(module.repository["infra"].deploy_keys), "work-laptop")
    error_message = "Deploy key work-laptop must be registered"
  }
}

run "verify_computed_outputs_on_apply" {
  command = apply

  variables {
    enable_prevent_destroy = false
  }

  assert {
    condition     = module.repository["infra"].repository_name == "infra"
    error_message = "Repository name must match infra on apply"
  }

  assert {
    condition     = length(keys(output.repositories)) > 0
    error_message = "Repositories output map must not be empty on apply"
  }

  assert {
    condition     = output.repository_html_url != ""
    error_message = "Primary repository HTML URL must not be empty on apply"
  }
}

