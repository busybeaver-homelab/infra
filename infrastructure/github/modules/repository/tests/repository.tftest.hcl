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

  assert {
    condition     = github_repository.repo.visibility == "public"
    error_message = "Default repository visibility must be public"
  }
}

run "verify_repository_module_apply" {
  command = apply

  assert {
    condition     = output.repository_name == "test-repo"
    error_message = "Repository name output must match"
  }

  assert {
    condition     = output.visibility == "public"
    error_message = "Repository visibility output must match"
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

run "verify_repository_private_visibility" {
  command = plan

  variables {
    visibility = "private"
  }

  assert {
    condition     = github_repository.repo.visibility == "private"
    error_message = "Repository visibility must be configurable to private"
  }
}

run "reject_invalid_visibility" {
  command = plan

  variables {
    visibility = "confidential"
  }

  expect_failures = [
    var.visibility,
  ]
}

