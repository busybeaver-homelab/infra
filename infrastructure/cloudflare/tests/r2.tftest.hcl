mock_provider "cloudflare" {}

variables {
  cloudflare_api_token  = "mock-cf-token-12345"
  cloudflare_account_id = "mock-account-id-12345"
}

run "verify_r2_backup_bucket_configuration" {
  command = plan

  assert {
    condition     = cloudflare_r2_bucket.backups_dr.name == "homelab-backups-dr"
    error_message = "R2 disaster recovery backup bucket must be named homelab-backups-dr"
  }

  assert {
    condition     = cloudflare_r2_bucket.backups_dr.location == "WEUR"
    error_message = "R2 disaster recovery backup bucket location hint must be WEUR for EU data residency"
  }
}
