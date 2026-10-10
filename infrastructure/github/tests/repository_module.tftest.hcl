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
    condition     = github_repository_environment.ci.environment == "ci"
    error_message = "CI environment must be defined"
  }

  assert {
    condition     = github_repository_environment.backup.environment == "backup"
    error_message = "Backup environment must be defined"
  }
}
