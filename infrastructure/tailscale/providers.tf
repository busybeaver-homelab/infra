provider "tailscale" {
  oauth_client_id     = local.tailscale_client_id
  oauth_client_secret = local.tailscale_client_secret
  tailnet             = local.tailnet_name
}
