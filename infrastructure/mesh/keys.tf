resource "tailscale_tailnet_key" "roles" {
  for_each      = var.auth_keys
  reusable      = each.value.reusable
  ephemeral     = each.value.ephemeral
  preauthorized = each.value.preauthorized
  expiry        = each.value.expiry
  description   = each.value.description
  tags          = each.value.tags
}

