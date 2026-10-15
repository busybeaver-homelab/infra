mock_provider "github" {}
mock_provider "sops" {}
mock_provider "external" {}

override_data {
  target = data.external.sops_github
  values = {
    result = {
      json = <<-EOT
        {
          "owner": "mock-owner",
          "config": {
            "repositories": {
              "infra": {
                "name": "infra",
                "description": "Infrastructure as Code for my homelab environment",
                "topics": ["homelab", "infrastructure-as-code", "iac"]
              }
            },
            "deploy_keys": {
              "work-laptop": {
                "title": "work-laptop",
                "key": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockKeyForTestingOnly0000000000000000000000",
                "read_only": true
              }
            }
          }
        }
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
    condition     = module.repository["infra"].merge_queue_enabled == true
    error_message = "Main branch ruleset must enable merge queue for infra repository"
  }

  assert {
    condition     = module.repository["infra"].ci_deployment_branch_patterns == tolist(["gh-readonly-queue/main/*", "main", "refs/pull/*/merge"])
    error_message = "CI environment must allow only main, pull_request merge refs and merge queue groups (STD-CI-23)"
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
    condition     = module.repository["infra"].environments.ops == "ops" && module.repository["infra"].ops_environment_name == "ops"
    error_message = "Ops environment must be defined"
  }

  assert {
    condition     = module.repository["infra"].backup_deployment_branch_pattern == "main"
    error_message = "Backup environment must restrict deployments to main"
  }

  assert {
    condition     = module.repository["infra"].ops_deployment_branch_pattern == "main"
    error_message = "Ops environment must restrict deployments to main"
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
    condition     = module.repository["infra"].actions_permissions.github_owned_allowed == true
    error_message = "Actions permissions must allow GitHub-owned actions"
  }

  assert {
    condition     = module.repository["infra"].actions_permissions.verified_allowed == false
    error_message = "Actions permissions must not blanket-allow all Marketplace verified actions"
  }

  assert {
    condition     = contains(module.repository["infra"].actions_permissions.patterns_allowed, "step-security/harden-runner@*")
    error_message = "Actions permissions must explicitly allow step-security/harden-runner@*"
  }

  assert {
    condition     = contains(keys(module.repository["infra"].deploy_keys), "work-laptop") && module.repository["infra"].deploy_keys["work-laptop"].read_only == true
    error_message = "Deploy key work-laptop must be registered from SOPS and strictly read_only"
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


run "merge_queue_root_override_disables_queue" {
  command = plan

  variables {
    enable_merge_queue = false
  }

  assert {
    condition     = module.repository["infra"].merge_queue_enabled == false
    error_message = "Root enable_merge_queue = false must disable the merge queue"
  }

  assert {
    condition     = module.repository["infra"].ci_deployment_branch_patterns == tolist(["main", "refs/pull/*/merge"])
    error_message = "CI environment must drop merge queue refs when the merge queue is disabled"
  }
}

run "ci_environment_holds_no_production_material" {
  command = plan

  assert {
    condition     = !contains(keys(local.ci_environment_secrets), "TOFU_ENCRYPTION_PASSPHRASE")
    error_message = "The production state passphrase must not be distributed to the ci environment."
  }

  assert {
    condition     = keys(local.ci_environment_secrets) == ["SOPS_AGE_KEY_CI"]
    error_message = "The ci environment must only receive the CI age identity."
  }

  assert {
    condition     = !contains(keys(local.backup_environment_secrets), "SOPS_AGE_KEY_CI")
    error_message = "SOPS_AGE_KEY_CI must not be injected into the backup environment (R2-CI-01)."
  }

  assert {
    condition     = !contains(keys(local.ops_environment_secrets), "SOPS_AGE_KEY_CI")
    error_message = "SOPS_AGE_KEY_CI must not be injected into the ops environment (R2-CI-01)."
  }

  assert {
    condition     = can(regex("^AGE-SECRET-KEY-1[0-9A-Z]{58}$", local.ci_age_key))
    error_message = "The CI age key must be exactly one identity."
  }
}
