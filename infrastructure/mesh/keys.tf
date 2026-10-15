resource "tailscale_tailnet_key" "bootstrap_oci" {
  reusable      = false
  ephemeral     = false
  preauthorized = true
  expiry        = var.bootstrap_key_expiry
  description   = "Homelab OCI automation bootstrap key"
  tags          = var.bootstrap_key_tags
}

resource "tailscale_tailnet_key" "bootstrap_gcp" {
  reusable      = false
  ephemeral     = false
  preauthorized = true
  expiry        = var.bootstrap_key_expiry
  description   = "Homelab GCP automation bootstrap key"
  tags          = var.bootstrap_gcp_key_tags
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

