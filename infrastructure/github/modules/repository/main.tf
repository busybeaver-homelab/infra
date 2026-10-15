resource "github_repository" "repo" {
  #checkov:skip=CKV_GIT_1:Repository visibility is configurable and defaults to public for open-source homelab infrastructure
  name        = var.repository_name
  description = var.description
  # kics-scan ignore-line
  visibility             = var.visibility
  has_issues             = false
  has_wiki               = false
  has_discussions        = false
  has_projects           = false
  delete_branch_on_merge = true
  allow_squash_merge     = true
  allow_auto_merge       = true
  allow_rebase_merge     = var.allow_rebase_merge
  allow_merge_commit     = var.allow_merge_commit
  topics                 = var.topics
  archive_on_destroy     = true

  squash_merge_commit_title   = "PR_TITLE"
  squash_merge_commit_message = "PR_BODY"

  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }
    secret_scanning_push_protection {
      status = "enabled"
    }
  }

  lifecycle {
    prevent_destroy = var.enable_prevent_destroy
  }
}

resource "github_repository_vulnerability_alerts" "repo" {
  repository = github_repository.repo.name
}

resource "github_repository_ruleset" "main_protection" {
  name        = "Protect Main Branch"
  repository  = github_repository.repo.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  # Owner decision D6: organization owners may push/merge to main directly (small,
  # local fast-forward merges; the pre-push guard requires ALLOW_MAIN_PUSH=1);
  # any other repository admin can only bypass through a pull request.
  # No actor_id: GitHub stores null for OrganizationAdmin and the provider reads it back as 0,
  # so a configured 1 is a perpetual diff (integrations/terraform-provider-github#2536, REV2-X-3).
  bypass_actors {
    actor_type  = "OrganizationAdmin"
    bypass_mode = "always"
  }

  bypass_actors {
    actor_id    = 5 # Repository Admin role
    actor_type  = "RepositoryRole"
    bypass_mode = "pull_request"
  }

  # NOTE: Dependabot and Renovate are intentionally commented out as bypass actors.
  # In GitHub Rulesets, placing an actor in bypass_actors grants permission to bypass ALL
  # rules (including required status checks and direct branch pushes to main).
  #
  # Automated dependency bots do NOT need bypass permissions to auto-merge PRs.
  # Because `allow_auto_merge = true` is enabled on the repository and `required_approving_review_count = 0`,
  # bots can enable auto-merge, and GitHub will automatically merge their PRs once and ONLY once
  # all required CI checks (CI Gate) are completely green.
  #
  # Keeping these blocks commented out ensures bots can NEVER push directly to main or bypass
  # CI checks, while still permitting fully automated PR merging upon successful CI.
  #
  # bypass_actors {
  #   actor_id    = 29110 # Dependabot
  #   actor_type  = "Integration"
  #   bypass_mode = "always"
  # }
  #
  # bypass_actors {
  #   actor_id    = 2740 # Renovate
  #   actor_type  = "Integration"
  #   bypass_mode = "always"
  # }

  rules {
    creation                = true
    deletion                = true
    required_linear_history = true
    required_signatures     = false

    pull_request {
      dismiss_stale_reviews_on_push     = true
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_approving_review_count   = 0
      required_review_thread_resolution = true
    }

    required_status_checks {
      strict_required_status_checks_policy = true

      required_check {
        context        = "CI Gate"
        integration_id = 15368 # GitHub Actions: only Actions can satisfy the required check
      }
    }

    dynamic "merge_queue" {
      for_each = coalesce(var.enable_merge_queue, var.visibility == "public") ? [1] : []
      content {
        check_response_timeout_minutes    = 60
        grouping_strategy                 = "ALLGREEN"
        max_entries_to_build              = 5
        max_entries_to_merge              = 5
        merge_method                      = "SQUASH"
        min_entries_to_merge              = 1
        min_entries_to_merge_wait_minutes = 0
      }
    }
  }
}

resource "github_repository_environment" "ci" {
  environment = "ci"
  repository  = github_repository.repo.name
}

resource "github_actions_environment_secret" "ci_secrets" {
  for_each    = nonsensitive(toset(keys(var.ci_secrets)))
  repository  = github_repository.repo.name
  environment = github_repository_environment.ci.environment
  secret_name = each.key
  value       = var.ci_secrets[each.key]
}

resource "github_repository_environment" "backup" {
  environment = "backup"
  repository  = github_repository.repo.name

  deployment_branch_policy {
    protected_branches     = true
    custom_branch_policies = false
  }
}

resource "github_actions_environment_secret" "backup_secrets" {
  for_each    = nonsensitive(toset(keys(var.backup_secrets)))
  repository  = github_repository.repo.name
  environment = github_repository_environment.backup.environment
  secret_name = each.key
  value       = var.backup_secrets[each.key]
}

resource "github_repository_environment" "code_quality" {
  environment = "code_quality"
  repository  = github_repository.repo.name
}

resource "github_actions_repository_permissions" "repo" {
  repository = github_repository.repo.name
  enabled    = true

  allowed_actions = "selected"

  sha_pinning_required = true
}

resource "github_workflow_repository_permissions" "repo" {
  repository                       = github_repository.repo.name
  default_workflow_permissions     = "read"
  can_approve_pull_request_reviews = false
}

resource "github_repository_dependabot_security_updates" "repo" {
  repository = github_repository.repo.name
  enabled    = true
}

resource "github_repository_deploy_key" "deploy_keys" {
  for_each   = var.deploy_keys
  repository = github_repository.repo.name
  title      = each.value.title
  key        = each.value.key
  read_only  = each.value.read_only
}

