data "github_repository" "repo" {
  name = var.repository_name
}

resource "github_branch_protection" "main_protection" {
  repository_id = data.github_repository.repo.node_id
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
