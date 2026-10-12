resource "tailscale_tailnet_key" "bootstrap" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = 7776000 # 90 days in seconds
  description   = "Homelab automation bootstrap key"
  tags          = var.bootstrap_key_tags
}

resource "tailscale_tailnet_key" "roles" {
  for_each      = var.auth_keys
  reusable      = each.value.reusable
  ephemeral     = each.value.ephemeral
  preauthorized = each.value.preauthorized
  expiry        = each.value.expiry
  description   = each.value.description
  tags          = each.value.tags
}

