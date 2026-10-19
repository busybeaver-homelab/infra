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
  sops_age_key_ci             = format("%s%s", "AGE-SECRET-KEY-1", join("", [for _ in range(58) : "Q"]))
  github_token                = "mock-ghp-token-12345"
  github_owner                = "mock-owner"
  enable_prevent_destroy      = false
}

# STD-OT-59: Repository governance, CodeQL scanning gate, and secret-tier isolation invariants.
run "policy_invariants" {
  command = plan

  assert {
    condition = (
      module.repository["infra"].allow_squash_merge == true &&
      module.repository["infra"].allow_merge_commit == false &&
      module.repository["infra"].allow_rebase_merge == false &&
      module.repository["infra"].delete_branch_on_merge == true &&
      module.repository["infra"].has_issues == true &&
      module.repository["infra"].dependabot_security_updates_enabled == false &&
      module.repository["infra"].ruleset_enforcement == "active" &&
      module.repository["infra"].merge_queue_enabled == true &&
      toset([
        for t in module.repository["infra"].ruleset_required_code_scanning_tools :
        t.tool
      ]) == toset(["CodeQL", "Trivy", "checkov", "shellcheck", "zizmor"]) &&
      alltrue([
        for t in module.repository["infra"].ruleset_required_code_scanning_tools :
        t.alerts_threshold == "errors" && t.security_alerts_threshold == "high_or_higher"
      ])
    )
    error_message = "GitHub repository ruleset must stay active with squash-only merges, merge queue, and all SARIF code scanning gates (STD-OT-52, STD-OT-59)."
  }

  assert {
    condition = (
      module.repository["infra"].actions_permissions.allowed_actions == "selected" &&
      module.repository["infra"].actions_permissions.sha_pinning_required == true &&
      module.repository["infra"].backup_deployment_branch_pattern == "main" &&
      module.repository["infra"].ops_deployment_branch_pattern == "main" &&
      keys(local.ci_environment_secrets) == ["SOPS_AGE_KEY_CI"] &&
      !contains(keys(local.backup_environment_secrets), "SOPS_AGE_KEY_CI") &&
      !contains(keys(local.ops_environment_secrets), "SOPS_AGE_KEY_CI") &&
      module.repository["infra"].deploy_keys["work-laptop"].read_only == false
    )
    error_message = "GitHub Actions permissions must require SHA pinning on selected actions, deploy key must retain read-write permissions to push code, and CI Age key must stay isolated to the ci environment (STD-OT-52, STD-OT-59)."
  }
}
