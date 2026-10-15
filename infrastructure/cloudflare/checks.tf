check "enforce_r2_bucket_posture" {
  assert {
    condition     = cloudflare_r2_bucket.tfstate.name == "homelab-infra-tfstate"
    error_message = "OpenTofu state R2 bucket must be named homelab-infra-tfstate"
  }

  assert {
    condition     = cloudflare_r2_bucket.tfstate.jurisdiction == "default"
    error_message = "OpenTofu state R2 bucket jurisdiction must be default"
  }

  # The API returns location hints upper-case ("WEUR") while the config uses lower-case (REV2-X-4).
  assert {
    condition     = lower(cloudflare_r2_bucket.backups_dr.location) == "weur"
    error_message = "Disaster recovery R2 bucket must be located in weur for EU data residency"
  }
}

check "enforce_account_security_posture" {
  assert {
    condition     = cloudflare_account.this.settings.enforce_twofactor == true
    error_message = "Cloudflare account must strictly enforce two-factor authentication"
  }
}
