check "enforce_repository_governance_posture" {
  assert {
    condition     = module.repository["infra"].ruleset_enforcement == "active"
    error_message = "Main branch ruleset protection must strictly be active on infra repository"
  }

  assert {
    condition     = module.repository["infra"].allow_squash_merge == true
    error_message = "Squash merge must strictly be enabled for clean commit history"
  }

  assert {
    condition     = module.repository["infra"].allow_merge_commit == false
    error_message = "Merge commits must be disabled to enforce squash merges"
  }

  assert {
    condition     = module.repository["infra"].allow_rebase_merge == false
    error_message = "Rebase merges must be disabled to enforce squash merges"
  }
}
