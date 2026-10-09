mock_provider "github" {}

variables {
  github_token    = "mock-ghp-token-12345"
  github_owner    = "mock-owner"
  repository_name = "homelab-infra"
}

run "reject_merge_commit_enabled" {
  command = plan

  variables {
    allow_merge_commit = true
  }

  expect_failures = [
    var.allow_merge_commit,
  ]
}

run "reject_rebase_merge_enabled" {
  command = plan

  variables {
    allow_rebase_merge = true
  }

  expect_failures = [
    var.allow_rebase_merge,
  ]
}
