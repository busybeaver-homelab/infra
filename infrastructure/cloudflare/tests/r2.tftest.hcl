mock_provider "cloudflare" {
  mock_data "cloudflare_api_token_permission_groups" {
    defaults = {
      account = {
        "Workers R2 Storage Bucket Item Read"  = "mock-perm-r2-read"
        "Workers R2 Storage Bucket Item Write" = "mock-perm-r2-write"
      }
    }
  }
}

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
    condition     = cloudflare_r2_bucket.backups_dr.location == "EEUR"
    error_message = "R2 disaster recovery backup bucket location hint must be EEUR for EU data residency"
  }
}
