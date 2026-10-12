resource "tailscale_tailnet_key" "bootstrap" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = 7776000 # 90 days in seconds
  description   = "Homelab automation bootstrap key"
  tags          = var.bootstrap_key_tags
}
