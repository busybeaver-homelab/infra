resource "github_repository" "repo" {
  name                   = var.repository_name
  description            = "Infrastructure as Code for my homelab environment"
  visibility             = "public"
  has_issues             = true
  has_wiki               = false
  has_projects           = false
  delete_branch_on_merge = true
  allow_squash_merge     = true
  allow_auto_merge       = true
  allow_rebase_merge     = false
  allow_merge_commit     = false
  topics                 = ["homelab", "infrastructure-as-code", "iac"]
  archive_on_destroy     = true

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

resource "github_branch_protection" "main_protection" {
  repository_id = github_repository.repo.node_id
  pattern       = "main"

  enforce_admins = true

  required_pull_request_reviews {
    dismiss_stale_reviews           = true
    require_code_owner_reviews      = false
    required_approving_review_count = 1
  }

  required_status_checks {
    strict   = true
    contexts = ["lint", "test"] # Standard CI status checks
  }
}

resource "github_repository_environment" "ci" {
  environment = "ci"
  repository  = github_repository.repo.name
}

resource "github_actions_environment_secret" "ci_secrets" {
  for_each        = nonsensitive(var.ci_secrets)
  repository      = github_repository.repo.name
  environment     = github_repository_environment.ci.environment
  secret_name     = each.key
  plaintext_value = each.value
}

resource "github_repository_environment" "production" {
  environment = "production"
  repository  = github_repository.repo.name

  reviewers {
    users = var.reviewers_for_production
  }
}

