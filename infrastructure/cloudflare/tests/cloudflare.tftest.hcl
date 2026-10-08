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

  assert {
    condition     = cloudflare_api_token.r2_state_token.name == "homelab-infra-r2-state-token"
    error_message = "Cloudflare R2 API token name must be homelab-infra-r2-state-token"
  }

  assert {
    condition     = length(cloudflare_api_token.r2_state_token.policy) == 1
    error_message = "Cloudflare R2 API token must have exactly one policy block"
  }

  assert {
    condition     = output.r2_access_key_id != null
    error_message = "r2_access_key_id output must not be null"
  }

  assert {
    condition     = output.r2_secret_access_key != null
    error_message = "r2_secret_access_key output must not be null"
  }
}
