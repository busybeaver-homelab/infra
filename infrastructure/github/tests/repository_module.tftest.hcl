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
    condition     = length(github_repository_ruleset.main_protection.bypass_actors) == 3
    error_message = "Ruleset must specify exactly 3 bypass actors (Admin, Dependabot, Renovate)"
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
    condition     = github_repository_environment.backup.environment == "backup"
    error_message = "Backup environment must be defined"
  }
}
