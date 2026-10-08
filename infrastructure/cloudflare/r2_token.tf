# --- Cloudflare R2 API Token for OpenTofu Remote State Backend ---
# Grants Object Read & Write permissions scoped to the remote state bucket.
# The S3 Access Key ID corresponds to the token ID, and the Secret Access Key
# corresponds to the SHA-256 hash of the generated token value.

data "cloudflare_api_token_permission_groups" "all" {}

resource "cloudflare_api_token" "r2_state_token" {
  name = "homelab-infra-r2-state-token"

  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.all.account["Workers R2 Storage Bucket Item Read"],
      data.cloudflare_api_token_permission_groups.all.account["Workers R2 Storage Bucket Item Write"]
    ]

    resources = {
      "com.cloudflare.edge.r2.bucket.${var.cloudflare_account_id}_default_${cloudflare_r2_bucket.tfstate.name}" = "*"
    }
  }
}
