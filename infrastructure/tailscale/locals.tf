locals {
  # Sensitive: decoded canonical SOPS credentials file.
  sops_data = yamldecode(data.sops_file.secrets.raw)

  # Tailscale provider credentials: use variable override if set, else read from SOPS.
  tailscale_client_id     = var.tailscale_client_id != "" ? var.tailscale_client_id : try(local.sops_data.tailscale.client_id, "")
  tailscale_client_secret = var.tailscale_client_secret != "" ? var.tailscale_client_secret : try(local.sops_data.tailscale.client_secret, "")
  tailnet_name            = var.tailnet_name != "" ? var.tailnet_name : try(local.sops_data.tailscale.config.tailnet_name, "")

  # Tailscale tailnet contact emails: read from SOPS credentials config.
  contact_account_email  = try(local.sops_data.tailscale.config.contact_account_email, "")
  contact_support_email  = try(local.sops_data.tailscale.config.contact_support_email, "")
  contact_security_email = try(local.sops_data.tailscale.config.contact_security_email, "")
}
