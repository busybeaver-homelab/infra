resource "github_repository" "repo" {
  name                   = var.repository_name
  description            = var.description
  visibility             = "public"
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
    prevent_destroy = true
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

  bypass_actors {
    actor_id    = 5 # Repository Admin
    actor_type  = "RepositoryRole"
    bypass_mode = "pull_request"
  }

  rules {
    creation                = true
    update                  = true
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
        context = "ci-gate"
      }
    }
  }
}

resource "github_repository_environment" "ci" {
  environment = "ci"
  repository  = github_repository.repo.name

  deployment_branch_policy {
    protected_branches     = true
    custom_branch_policies = false
  }
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
