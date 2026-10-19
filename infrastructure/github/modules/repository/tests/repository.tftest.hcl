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

  assert {
    condition     = github_repository.repo.has_issues == true
    error_message = "GitHub Issues must be enabled for Renovate Dependency Dashboard (R2-REN-05)"
  }

  assert {
    condition     = github_repository_vulnerability_alerts.repo.repository == "test-repo" && github_repository_dependabot_security_updates.repo.enabled == false
    error_message = "Vulnerability alerts must stay enabled while duplicate Dependabot security update PRs are disabled (R2-REN-05)"
  }

  assert {
    condition     = length(github_repository_ruleset.main_protection.rules[0].merge_queue) == 1
    error_message = "Public repository must enable merge_queue in main_protection ruleset"
  }

  assert {
    condition     = github_repository_ruleset.main_protection.rules[0].merge_queue[0].merge_method == "SQUASH"
    error_message = "Merge queue must enforce SQUASH merge method (STD-CI-68)"
  }

  assert {
    condition     = github_repository_ruleset.main_protection.rules[0].merge_queue[0].grouping_strategy == "ALLGREEN"
    error_message = "Merge queue must use ALLGREEN grouping strategy"
  }

  assert {
    condition     = github_repository_ruleset.main_protection.rules[0].merge_queue[0].min_entries_to_merge == 1
    error_message = "Merge queue must allow immediate single-PR merges (min_entries_to_merge = 1)"
  }

  assert {
    condition     = github_repository_ruleset.main_protection.rules[0].merge_queue[0].min_entries_to_merge_wait_minutes == 0
    error_message = "Merge queue must not wait before starting single-PR checks (min_entries_to_merge_wait_minutes = 0)"
  }

  assert {
    condition     = github_repository_ruleset.main_protection.rules[0].merge_queue[0].max_entries_to_merge == 5
    error_message = "Merge queue must batch up to 5 entries to merge"
  }

  assert {
    condition     = github_repository_ruleset.main_protection.rules[0].merge_queue[0].max_entries_to_build == 5
    error_message = "Merge queue must speculatively build up to 5 entries in parallel"
  }

  assert {
    condition     = github_repository_ruleset.main_protection.rules[0].merge_queue[0].check_response_timeout_minutes == 60
    error_message = "Merge queue check response timeout must be 60 minutes"
  }

  assert {
    condition     = github_repository_environment.ci.deployment_branch_policy[0].protected_branches == false && github_repository_environment.ci.deployment_branch_policy[0].custom_branch_policies == true
    error_message = "ci environment must use an explicit ref allowlist; protected_branches lets every branch deploy when main is protected only by a ruleset (STD-CI-23)"
  }

  assert {
    condition     = toset(keys(github_repository_environment_deployment_policy.ci)) == toset(["main", "refs/pull/*/merge", "gh-readonly-queue/main/*"])
    error_message = "ci environment must allow exactly main, pull_request merge refs and merge queue groups (STD-CI-23)"
  }

  assert {
    condition     = alltrue([for policy in github_repository_environment_deployment_policy.ci : policy.environment == "ci" && policy.tag_pattern == null])
    error_message = "ci deployment policies must target the ci environment with branch patterns only"
  }

  assert {
    condition     = github_repository_environment.backup.deployment_branch_policy[0].protected_branches == false && github_repository_environment.backup.deployment_branch_policy[0].custom_branch_policies == true
    error_message = "backup environment must use custom_branch_policies (R2-CI-01)"
  }

  assert {
    condition     = github_repository_environment_deployment_policy.backup_main.branch_pattern == "main"
    error_message = "backup environment must restrict deployments to main (R2-CI-01)"
  }

  assert {
    condition     = github_repository_environment.ops.environment == "ops"
    error_message = "ops environment must be defined (R2-CI-01)"
  }

  assert {
    condition     = github_repository_environment.ops.deployment_branch_policy[0].protected_branches == false && github_repository_environment.ops.deployment_branch_policy[0].custom_branch_policies == true
    error_message = "ops environment must use custom_branch_policies (R2-CI-01)"
  }

  assert {
    condition     = github_repository_environment_deployment_policy.ops_main.branch_pattern == "main"
    error_message = "ops environment must restrict deployments to main (R2-CI-01)"
  }

  # allowed_actions_config is managed at the organization level (see main.tf comment):
  # assert {
  #   condition     = github_actions_repository_permissions.repo.allowed_actions_config[0].github_owned_allowed == true
  #   error_message = "Actions permissions must allow GitHub-owned actions (R2-GOV-01)"
  # }
  #
  # assert {
  #   condition     = github_actions_repository_permissions.repo.allowed_actions_config[0].verified_allowed == false
  #   error_message = "Actions permissions must disable verified_allowed (R2-GOV-01)"
  # }
  #
  # assert {
  #   condition     = contains(github_actions_repository_permissions.repo.allowed_actions_config[0].patterns_allowed, "step-security/harden-runner@*")
  #   error_message = "Actions permissions must allow step-security/harden-runner@* (R2-GOV-01)"
  # }
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
    condition     = output.merge_queue_enabled == true
    error_message = "Merge queue output must be true for public repositories"
  }

  assert {
    condition     = output.ci_deployment_branch_patterns == tolist(["gh-readonly-queue/main/*", "main", "refs/pull/*/merge"])
    error_message = "ci_deployment_branch_patterns output must list the sorted ci allowlist"
  }

  assert {
    condition     = output.actions_permissions.allowed_actions == "selected"
    error_message = "Actions permissions must restrict allowed actions to selected"
  }

  assert {
    condition     = output.ops_environment_name == "ops" && output.environments.ops == "ops"
    error_message = "ops environment outputs must be populated"
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

  assert {
    condition     = length(github_repository_ruleset.main_protection.rules[0].merge_queue) == 0
    error_message = "Private repository on Free org plan must default merge_queue to disabled unless explicitly enabled"
  }

  assert {
    condition     = toset(keys(github_repository_environment_deployment_policy.ci)) == toset(["main", "refs/pull/*/merge"])
    error_message = "ci environment must not allow merge queue refs when the merge queue is disabled"
  }
}

run "verify_merge_queue_explicit_disable" {
  command = plan

  variables {
    enable_merge_queue = false
  }

  assert {
    condition     = length(github_repository_ruleset.main_protection.rules[0].merge_queue) == 0
    error_message = "enable_merge_queue = false must disable the merge queue on a public repository"
  }

  assert {
    condition     = !contains(keys(github_repository_environment_deployment_policy.ci), "gh-readonly-queue/main/*")
    error_message = "ci environment must not allow merge queue refs when the merge queue is disabled"
  }
}

run "verify_merge_queue_explicit_enable_on_private" {
  command = plan

  variables {
    visibility         = "private"
    enable_merge_queue = true
  }

  assert {
    condition     = length(github_repository_ruleset.main_protection.rules[0].merge_queue) == 1
    error_message = "enable_merge_queue = true must override the private-visibility default"
  }

  assert {
    condition     = contains(keys(github_repository_environment_deployment_policy.ci), "gh-readonly-queue/main/*")
    error_message = "ci environment must allow merge queue refs whenever the merge queue is enabled"
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

run "reject_state_passphrase_in_ops_environment" {
  command = plan

  variables {
    ops_secrets = {
      STATE_PASSPHRASE = "never-distribute-this-0000000000000000"
    }
  }

  expect_failures = [
    var.ops_secrets,
  ]
}

run "reject_sops_age_key_ci_in_backup_environment" {
  command = plan

  variables {
    backup_secrets = {
      SOPS_AGE_KEY_CI = format("%s%s", "AGE-SECRET-KEY-1", join("", [for _ in range(58) : "Q"]))
    }
  }

  expect_failures = [
    var.backup_secrets,
  ]
}

run "reject_sops_age_key_ci_in_ops_environment" {
  command = plan

  variables {
    ops_secrets = {
      SOPS_AGE_KEY_CI = format("%s%s", "AGE-SECRET-KEY-1", join("", [for _ in range(58) : "Q"]))
    }
  }

  expect_failures = [
    var.ops_secrets,
  ]
}

run "accept_writable_deploy_key" {
  command = plan

  variables {
    deploy_keys = {
      "writable" = {
        title     = "writable"
        key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockKeyForTestingOnly0000000000000000000000"
        read_only = false
      }
    }
  }

  assert {
    condition     = github_repository_deploy_key.deploy_keys["writable"].read_only == false
    error_message = "Writable deploy keys (read_only = false) must be accepted because write access is required to push code."
  }
}

run "reject_deploy_key_with_email_comment" {
  command = plan

  variables {
    deploy_keys = {
      "email" = {
        title     = "email"
        key       = format("%s %s%s%s", "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockKeyForTestingOnly0000000000000000000000", "user", "\u0040", "example.test")
        read_only = true
      }
    }
  }

  expect_failures = [
    var.deploy_keys,
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
      for a in github_repository_ruleset.main_protection.bypass_actors :
      coalesce(a.actor_id, 0) == 0 if a.actor_type == "OrganizationAdmin"
    ])
    error_message = "OrganizationAdmin must not set actor_id: GitHub stores null and a configured value is a perpetual diff."
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

  assert {
    condition = (
      toset([
        for t in github_repository_ruleset.main_protection.rules[0].required_code_scanning[0].required_code_scanning_tool :
        t.tool
      ]) == toset(["CodeQL", "Trivy", "checkov", "shellcheck", "zizmor"]) &&
      alltrue([
        for t in github_repository_ruleset.main_protection.rules[0].required_code_scanning[0].required_code_scanning_tool :
        t.alerts_threshold == "errors" && t.security_alerts_threshold == "high_or_higher"
      ])
    )
    error_message = "Main branch ruleset must require all SARIF code scanning tools (CodeQL, Trivy, checkov, shellcheck, zizmor) with alerts_threshold = errors and security_alerts_threshold = high_or_higher (R2-CI-07)."
  }
}
