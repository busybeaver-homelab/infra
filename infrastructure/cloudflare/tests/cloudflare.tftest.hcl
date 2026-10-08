mock_provider "cloudflare" {}

variables {
  cloudflare_api_token  = "mock-cf-token-12345"
  cloudflare_zone_id    = "mock-zone-id-12345"
  cloudflare_account_id = "mock-account-id-12345"
}

run "verify_cloudflare_core_resources" {
  command = plan

  assert {
    condition     = cloudflare_record.root_record.name == "@"
    error_message = "Root record name must be @"
  }

  assert {
    condition     = cloudflare_record.root_record.proxied == true
    error_message = "Root DNS record must be proxied through Cloudflare"
  }

  assert {
    condition     = cloudflare_r2_bucket.tfstate.name == "homelab-infra-tfstate"
    error_message = "OpenTofu state R2 bucket must be named homelab-infra-tfstate"
  }

  assert {
    condition     = cloudflare_r2_bucket.tfstate.location == "WEUR"
    error_message = "OpenTofu state R2 bucket location must be WEUR"
  }
}
