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


run "reject_state_passphrase_in_ci_environment" {
  command = plan

  variables {
    ci_secrets = {
      TOFU_ENCRYPTION_PASSPHRASE = "never-distribute-this-0000000000000000"
    }
  }

  expect_failures = [
    var.ci_secrets,
  ]
}

run "reject_state_passphrase_in_backup_environment" {
  command = plan

  variables {
    backup_secrets = {
      STATE_PASSPHRASE = "never-distribute-this-0000000000000000"
    }
  }

  expect_failures = [
    var.backup_secrets,
  ]
}

run "reject_keyring_or_decoy_as_ci_age_key" {
  command = plan

  variables {
    ci_secrets = {
      SOPS_AGE_KEY_CI = "AGE-SECRET-KEY-SYNTHETIC-DECOY-DUMMY-VALUE-FOR-TESTS"
    }
  }

  expect_failures = [
    var.ci_secrets,
  ]
}

run "accept_single_ci_age_identity" {
  command = plan

  variables {
    ci_secrets = {
      SOPS_AGE_KEY_CI = format("%s%s", "AGE-SECRET-KEY-1", join("", [for _ in range(58) : "Q"]))
    }
  }

  assert {
    condition     = length(github_actions_environment_secret.ci_secrets) == 1
    error_message = "A single valid CI age identity must be accepted."
  }
}

run "ruleset_bypass_and_required_check_follow_owner_decision" {
  command = plan

  assert {
    condition = alltrue([
      for a in github_repository_ruleset.main_protection.bypass_actors :
      (a.actor_type == "OrganizationAdmin" && a.bypass_mode == "always") ||
      (a.actor_type == "RepositoryRole" && a.bypass_mode == "pull_request")
    ])
    error_message = "Only organization owners may bypass always; repository admins may bypass only via pull request."
  }

  assert {
    condition     = length(github_repository_ruleset.main_protection.bypass_actors) == 2
    error_message = "Exactly two bypass actors (organization owners, repository admins) are allowed; no bots."
  }

  assert {
    condition = alltrue([
      for c in github_repository_ruleset.main_protection.rules[0].required_status_checks[0].required_check :
      c.integration_id == 15368
    ])
    error_message = "Required checks must be pinned to the GitHub Actions app (integration_id 15368)."
  }

  assert {
    condition     = github_repository_ruleset.main_protection.rules[0].required_linear_history == true
    error_message = "main must keep linear history (no merge commits, also for owner local merges)."
  }
}
