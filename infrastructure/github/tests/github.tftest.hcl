mock_provider "github" {}

variables {
  github_token    = "mock-ghp-token-12345"
  github_owner    = "mock-owner"
  repository_name = "homelab-infra"
}

run "verify_github_repository_hardening" {
  command = plan

  assert {
    condition     = github_repository.repo.name == "homelab-infra"
    error_message = "Repository name must match homelab-infra"
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
    condition     = github_repository_environment.production.environment == "production"
    error_message = "Production environment must be defined"
  }
}
