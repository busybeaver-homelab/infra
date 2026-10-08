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

run "verify_r2_api_token_configuration" {
  command = plan

  assert {
    condition     = cloudflare_api_token.r2_state_token.name == "homelab-infra-r2-state-token"
    error_message = "R2 API token name must be homelab-infra-r2-state-token"
  }

  assert {
    condition     = tolist(cloudflare_api_token.r2_state_token.policy)[0].permission_groups == toset(["mock-perm-r2-read", "mock-perm-r2-write"])
    error_message = "R2 API token must include both read and write permission groups for Object Read & Write"
  }

  assert {
    condition     = tolist(cloudflare_api_token.r2_state_token.policy)[0].resources["com.cloudflare.edge.r2.bucket.mock-account-id-12345_default_homelab-infra-tfstate"] == "*"
    error_message = "R2 API token must be scoped to the homelab-infra-tfstate bucket resource"
  }

  assert {
    condition     = output.r2_access_key_id != null
    error_message = "r2_access_key_id output must be defined and non-null"
  }

  assert {
    condition     = output.r2_secret_access_key != null
    error_message = "r2_secret_access_key output must be defined and non-null"
  }
}
