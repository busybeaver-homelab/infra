# Decrypts the canonical credentials file at plan time; all identifying Cloudflare
# configuration lives under cloudflare.config (see secrets/README.md).
data "sops_file" "secrets" {
  source_file = var.secrets_file_path
}

# Public permission-group catalog, used to resolve the frozen tokens' permission names to IDs.
data "cloudflare_account_api_token_permission_groups_list" "all" {
  account_id = var.cloudflare_account_id
  max_items  = 2000
}

# Live account tokens: guards the frozen token resources against silent re-creation.
data "cloudflare_account_tokens" "all" {
  account_id = var.cloudflare_account_id
  max_items  = 200
}

# Account permission group granted to the frozen member, resolved by name.
data "cloudflare_account_permission_groups" "frozen_member" {
  account_id = var.cloudflare_account_id
  name       = local.frozen_member_permission_group
}
