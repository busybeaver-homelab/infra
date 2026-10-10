mock_provider "github" {}

variables {
  repository_name        = "test-repo"
  description            = "Mock test repository"
  topics                 = ["homelab", "iac"]
  enable_prevent_destroy = false
}

run "verify_repository_module_plan" {
  command = plan

  assert {
    condition     = github_repository.repo.name == "test-repo"
    error_message = "Repository name must match input parameter"
  }

  assert {
    condition     = github_repository.repo.allow_squash_merge == true
    error_message = "Repository must enforce squash merge"
  }

  assert {
    condition     = github_repository.repo.allow_merge_commit == false
    error_message = "Repository must reject merge commits"
  }

  assert {
    condition     = github_repository.repo.delete_branch_on_merge == true
    error_message = "Repository must delete head branch upon merge"
  }
}

run "verify_repository_module_apply" {
  command = apply

  assert {
    condition     = output.repository_name == "test-repo"
    error_message = "Repository name output must match"
  }

  assert {
    condition     = output.ruleset_enforcement == "active"
    error_message = "Main branch ruleset must be actively enforced"
  }

  assert {
    condition     = output.actions_permissions.allowed_actions == "selected"
    error_message = "Actions permissions must restrict allowed actions to selected"
  }
}
