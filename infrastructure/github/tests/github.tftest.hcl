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
          },
          "deploy_keys": {
            "work-laptop": {
              "title": "work-laptop",
              "key": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockKeyForTestingOnly0000000000000000000000",
              "read_only": false
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

run "verify_github_root_hardening" {
  command = plan

  assert {
    condition     = !contains(keys(local.github_config), "token") && !contains(keys(local.github_config), "owner") && !contains(keys(local.github_config), "ci_age_key")
    error_message = "local.github_config (backed by data.external) must never carry token, owner, or ci_age_key (R2-TF-02)"
  }

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
    condition     = module.repository["infra"].has_issues == true && module.repository["infra"].dependabot_security_updates_enabled == false
    error_message = "GitHub Issues must be enabled for Renovate Dependency Dashboard and Dependabot security PRs disabled (R2-REN-05)"
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
    condition = (
      toset([
        for t in module.repository["infra"].ruleset_required_code_scanning_tools :
        t.tool
      ]) == toset(["CodeQL", "Trivy", "checkov", "shellcheck", "zizmor"]) &&
      alltrue([
        for t in module.repository["infra"].ruleset_required_code_scanning_tools :
        t.alerts_threshold == "errors" && t.security_alerts_threshold == "high_or_higher"
      ])
    )
    error_message = "Main branch ruleset must require all SARIF code scanning tools (CodeQL, Trivy, checkov, shellcheck, zizmor) with alerts_threshold = errors and security_alerts_threshold = high_or_higher (R2-CI-07)"
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
    condition     = !contains(module.repository["infra"].managed_secret_environments, "code_quality")
    error_message = "No github_actions_environment_secret resource may target the code_quality environment (R2-TF-02)"
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
    condition     = contains(module.repository["infra"].actions_permissions.allowed_action_patterns, "step-security/harden-runner@*")
    error_message = "Actions permissions must explicitly list step-security/harden-runner@* in allowed_action_patterns"
  }

  assert {
    condition     = contains(keys(module.repository["infra"].deploy_keys), "work-laptop") && module.repository["infra"].deploy_keys["work-laptop"].read_only == false
    error_message = "Deploy key work-laptop must be registered from SOPS with read_only = false (read-write permissions required to push code)"
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
