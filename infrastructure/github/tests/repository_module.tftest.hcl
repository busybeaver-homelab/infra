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
        key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINhE5DoHICY85bnMIzXRGkggJ97ekZaJtzpQ6I7JgfF0 jmollner@liveperson.com"
        read_only = false
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

  assert {
    condition     = github_workflow_repository_permissions.repo.default_workflow_permissions == "read"
    error_message = "Default workflow permissions must be read"
  }

  assert {
    condition     = github_workflow_repository_permissions.repo.can_approve_pull_request_reviews == false
    error_message = "Workflows must not be allowed to approve pull requests"
  }

  assert {
    condition     = github_repository_dependabot_security_updates.repo.enabled == true
    error_message = "Dependabot security updates must be enabled"
  }

  assert {
    condition     = github_repository_deploy_key.deploy_keys["work-laptop"].read_only == false
    error_message = "Deploy key work-laptop must have write access (read_only = false)"
  }

  assert {
    condition     = github_repository_environment.ci.environment == "ci"
    error_message = "CI environment must be defined"
  }

  assert {
    condition     = length(github_repository_environment.ci.deployment_branch_policy) == 0
    error_message = "CI environment must not restrict deployment_branch_policy so merge_group branches can deploy (STD-CI-23)"
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
    condition     = github_repository_environment.code_quality.environment == "code_quality"
    error_message = "Code quality environment must be defined"
  }
}
