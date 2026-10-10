# FROZEN: imported for documentation only. OpenTofu must never update, replace or destroy
# these (lock-out / self-modification risk). Consequence: drift on them is NOT reported.
# Guarded by tests/scripts/cloudflare-guards.bats.

locals {
  # Logical key => token name. Policies (who may do what) are security topology and live in
  # SOPS: cloudflare.config.iam.tokens.<key>.policies[] = {effect, resources, permission_groups}.
  frozen_token_names = {
    grafana   = "Grafana: Read analytics, logs and radar"
    r2_state  = "homelab-infra-opentofu-state-r2-token"
    terraform = "terraform-homelab-manually-provisioned"
  }

  live_token_names = [for t in data.cloudflare_account_tokens.all.result : t.name]
}

resource "cloudflare_account_token" "frozen" {
  for_each = local.frozen_token_names

  account_id = var.cloudflare_account_id
  name       = each.value

  policies = [
    for p in local.cf.iam.tokens[each.key].policies : {
      effect    = p.effect
      resources = p.resources
      permission_groups = [
        for g in p.permission_groups : { id = lookup(local.permission_group_ids, g, "unresolved:${g}") }
      ]
    }
  ]

  lifecycle {
    prevent_destroy = var.enable_prevent_destroy
    ignore_changes  = all

    # ignore_changes/prevent_destroy do not stop *creation*: if a frozen token was deleted outside
    # OpenTofu, fail instead of silently minting a new one. (An empty list only occurs with mocks.)
    precondition {
      condition     = length(local.live_token_names) == 0 || contains(local.live_token_names, each.value)
      error_message = "A frozen account token no longer exists in Cloudflare; OpenTofu would re-create it. Remove it from local.frozen_token_names and from state (tofu state rm) instead."
    }
  }
}

locals {
  frozen_member_permission_group = "Super Administrator - All Privileges"
  frozen_member_permission_group_id = try(
    one(data.cloudflare_account_permission_groups.frozen_member.result).id,
    "unresolved:${local.frozen_member_permission_group}",
  )
}

# Super Administrator membership of the account owner (account-scoped resource group from SOPS).
resource "cloudflare_account_member" "frozen" {
  account_id = var.cloudflare_account_id
  email      = local.cf.iam.member.email

  policies = [{
    access            = "allow"
    permission_groups = [{ id = local.frozen_member_permission_group_id }]
    resource_groups   = [{ id = local.cf.iam.member.resource_group_id }]
  }]

  lifecycle {
    prevent_destroy = var.enable_prevent_destroy
    ignore_changes  = all
  }
}

# An empty catalog only occurs with mocked providers (tests); real plans always return entries.
check "frozen_iam_references_resolve" {
  assert {
    condition = length(local.permission_group_ids) == 0 || nonsensitive(alltrue(flatten([
      for k in keys(local.frozen_token_names) : [
        for p in local.cf.iam.tokens[k].policies : [for g in p.permission_groups : contains(keys(local.permission_group_ids), g)]
      ]
    ])))
    error_message = "A frozen token permission group no longer resolves in the Cloudflare catalog (renamed or removed)."
  }

  assert {
    condition     = length(data.cloudflare_account_permission_groups.frozen_member.result) == 0 || !startswith(local.frozen_member_permission_group_id, "unresolved:")
    error_message = "The frozen member's permission group no longer resolves to exactly one Cloudflare permission group."
  }
}
