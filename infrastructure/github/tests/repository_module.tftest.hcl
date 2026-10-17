mock_provider "github" {}

run "verify_repository_child_module" {
  command = plan
  module {
    source = "./modules/repository"
  }

  variables {
    repository_name = "infra"
    description     = "Infrastructure as Code for my homelab environment"
    topics          = ["homelab", "infrastructure-as-code", "iac"]
    deploy_keys = {
      "work-laptop" = {
        title     = "work-laptop"
        key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockKeyForTestingOnly0000000000000000000000"
        read_only = true
      }
    }
  }

  assert {
    condition     = github_repository.repo.name == "infra"
    error_message = "Repository name must match infra"
  }

  assert {
    condition     = github_repository.repo.allow_squash_merge == true
    error_message = "Repository must allow squash merge"
  }

  assert {
    condition     = github_repository.repo.allow_merge_commit == false
    error_message = "Repository must disallow merge commits"
  }

  assert {
    condition     = github_repository.repo.allow_rebase_merge == false
    error_message = "Repository must disallow rebase commits"
  }

  assert {
    condition     = github_repository.repo.delete_branch_on_merge == true
    error_message = "Repository must delete head branch on merge"
  }

  assert {
    condition     = github_repository_ruleset.main_protection.enforcement == "active"
    error_message = "Main branch ruleset must be actively enforced"
  }

  assert {
    condition     = length(github_repository_ruleset.main_protection.bypass_actors) == 2
    error_message = "Ruleset must specify exactly 2 bypass actors (Organization Admin always, Repository Admin via pull request)"
  }

  assert {
    condition = alltrue([
      for a in github_repository_ruleset.main_protection.bypass_actors :
      (a.actor_type == "OrganizationAdmin" && a.bypass_mode == "always") ||
      (a.actor_type == "RepositoryRole" && a.bypass_mode == "pull_request")
    ])
    error_message = "Only organization owners may bypass always; repository admins may bypass only via pull request."
  }

  assert {
    condition     = tolist(github_repository_ruleset.main_protection.rules[0].required_status_checks[0].required_check)[0].context == "CI Gate"
    error_message = "Required status check context must match CI Gate"
  }

  assert {
    condition     = tolist(github_repository_ruleset.main_protection.rules[0].required_status_checks[0].required_check)[0].integration_id == 15368
    error_message = "Required status check must be pinned to GitHub Actions (integration_id 15368)"
  }

  assert {
    condition     = github_repository_ruleset.main_protection.rules[0].update == null || github_repository_ruleset.main_protection.rules[0].update == false
    error_message = "Main branch ruleset must not restrict updates so that PRs can be merged"
  }

  assert {
    condition     = github_repository_ruleset.main_protection.rules[0].deletion == true
    error_message = "Main branch ruleset must prevent deletion"
  }

  assert {
    condition     = github_repository_ruleset.main_protection.rules[0].required_linear_history == true
    error_message = "Main branch ruleset must require linear history"
  }

  assert {
    condition     = github_actions_repository_permissions.repo.allowed_actions == "selected"
    error_message = "Allowed actions must be set to selected"
  }

  assert {
    condition     = github_actions_repository_permissions.repo.sha_pinning_required == true
    error_message = "Actions must require full-length commit SHA pinning"
  }

  # allowed_actions_config is managed at the organization level (see main.tf comment):
  # assert {
  #   condition     = github_actions_repository_permissions.repo.allowed_actions_config[0].github_owned_allowed == true
  #   error_message = "Actions permissions must allow GitHub-owned actions"
  # }
  #
  # assert {
  #   condition     = github_actions_repository_permissions.repo.allowed_actions_config[0].verified_allowed == false
  #   error_message = "Actions permissions must not blanket-allow all Marketplace verified actions"
  # }
  #
  # assert {
  #   condition     = contains(github_actions_repository_permissions.repo.allowed_actions_config[0].patterns_allowed, "step-security/harden-runner@*")
  #   error_message = "Actions permissions must explicitly allow step-security/harden-runner@*"
  # }

  assert {
    condition     = github_workflow_repository_permissions.repo.default_workflow_permissions == "read"
    error_message = "Default workflow permissions must be read"
  }

  assert {
    condition     = github_workflow_repository_permissions.repo.can_approve_pull_request_reviews == false
    error_message = "Workflows must not be allowed to approve pull requests"
  }

  assert {
    condition     = github_repository.repo.has_issues == true
    error_message = "GitHub Issues must be enabled for Renovate Dependency Dashboard (R2-REN-05)"
  }

  assert {
    condition     = github_repository_vulnerability_alerts.repo.repository == "infra" && github_repository_dependabot_security_updates.repo.enabled == false
    error_message = "Dependabot security update PRs must be disabled in favor of Renovate while vulnerability alerts stay enabled (R2-REN-05)"
  }

  assert {
    condition     = github_repository_deploy_key.deploy_keys["work-laptop"].read_only == true
    error_message = "Deploy key work-laptop must enforce read_only = true (R2-TF-08)"
  }

  assert {
    condition     = github_repository_environment.ci.environment == "ci"
    error_message = "CI environment must be defined"
  }

  assert {
    condition     = github_repository_environment.ci.deployment_branch_policy[0].custom_branch_policies == true
    error_message = "CI environment must restrict deployments to an explicit ref allowlist (STD-CI-23)"
  }

  assert {
    condition     = toset(keys(github_repository_environment_deployment_policy.ci)) == toset(["main", "refs/pull/*/merge", "gh-readonly-queue/main/*"])
    error_message = "CI environment must allow exactly main, pull_request merge refs and merge queue groups (STD-CI-23)"
  }

  assert {
    condition     = github_repository_ruleset.main_protection.rules[0].merge_queue[0].merge_method == "SQUASH"
    error_message = "Main branch ruleset merge_queue must enforce SQUASH merge method"
  }

  assert {
    condition     = github_repository_ruleset.main_protection.rules[0].merge_queue[0].grouping_strategy == "ALLGREEN"
    error_message = "Main branch ruleset merge_queue must use ALLGREEN grouping strategy"
  }

  assert {
    condition     = github_repository_environment.backup.environment == "backup"
    error_message = "Backup environment must be defined"
  }

  assert {
    condition     = github_repository_environment.backup.deployment_branch_policy[0].custom_branch_policies == true && github_repository_environment_deployment_policy.backup_main.branch_pattern == "main"
    error_message = "Backup environment must restrict deployments to main via custom_branch_policies (R2-CI-01)"
  }

  assert {
    condition     = github_repository_environment.ops.environment == "ops"
    error_message = "Ops environment must be defined"
  }

  assert {
    condition     = github_repository_environment.ops.deployment_branch_policy[0].custom_branch_policies == true && github_repository_environment_deployment_policy.ops_main.branch_pattern == "main"
    error_message = "Ops environment must restrict deployments to main via custom_branch_policies (R2-CI-01)"
  }

  assert {
    condition     = github_repository_environment.code_quality.environment == "code_quality"
    error_message = "Code quality environment must be defined"
  }
}
