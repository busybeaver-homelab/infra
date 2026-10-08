mock_provider "cloudflare" {}

variables {
  cloudflare_api_token  = "mock-cf-token-12345"
  cloudflare_account_id = "mock-account-id-12345"
}

run "verify_cloudflare_core_resources" {
  command = plan

  assert {
    condition     = cloudflare_r2_bucket.tfstate.name == "homelab-infra-tfstate"
    error_message = "OpenTofu state R2 bucket must be named homelab-infra-tfstate"
  }

  assert {
    condition     = cloudflare_r2_bucket.tfstate.location == "WEUR"
    error_message = "OpenTofu state R2 bucket location must be WEUR"
  }
}
