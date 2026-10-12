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

  # Maps hostname (short name before first dot) to node ID
  discovered_device_ids = {
    for d in try(data.tailscale_devices.all.devices, []) :
    split(".", d.name)[0] => d.id
  }

  device_id_map = merge(
    local.discovered_device_ids,
    var.device_id_overrides
  )

  # Single source of truth for tailnet tag ownership (max 50 tags on Always Free Tier)
  tag_owners = {
    "tag:type-server"       = ["autogroup:owner", "tag:type-server"]
    "tag:type-client"       = ["autogroup:owner"]
    "tag:type-nas"          = ["autogroup:owner", "tag:type-server"]
    "tag:type-network"      = ["autogroup:owner", "tag:type-server"]
    "tag:type-docker"       = ["autogroup:owner", "tag:type-server"]
    "tag:os-linux"          = ["autogroup:owner", "tag:type-server"]
    "tag:os-windows"        = ["autogroup:owner"]
    "tag:os-macos"          = ["autogroup:owner"]
    "tag:os-ios"            = ["autogroup:owner"]
    "tag:os-appletv"        = ["autogroup:owner"]
    "tag:device-desktop"    = ["autogroup:owner"]
    "tag:device-mobile"     = ["autogroup:owner"]
    "tag:hosting-onpremise" = ["autogroup:owner", "tag:type-server"]
    "tag:hosting-cloud"     = ["autogroup:owner", "tag:type-server"]
    "tag:location-us"       = ["autogroup:owner", "tag:type-server"]
    "tag:location-ger"      = ["autogroup:owner", "tag:type-server"]
    "tag:env-gcp"           = ["autogroup:owner", "tag:type-server"]
    "tag:env-aws"           = ["autogroup:owner", "tag:type-server"]
    "tag:env-oci"           = ["autogroup:owner", "tag:type-server"]
    "tag:env-cloudflare"    = ["autogroup:owner", "tag:type-server"]
    "tag:svc-beszel"        = ["autogroup:owner", "tag:type-server"]
    "tag:svc-node-red"      = ["autogroup:owner", "tag:type-server"]
    "tag:svc-adguard"       = ["autogroup:owner", "tag:type-server"]
  }
}

