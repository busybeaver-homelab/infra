locals {
  ephemeral_sops_data = yamldecode(ephemeral.sops_file.secrets.raw)
  sops_config         = jsondecode(data.external.sops_config.result.json)

  # Tailscale provider credentials: use variable override if set, else read from ephemeral SOPS.
  tailscale_client_id     = var.tailscale_client_id != null && trimspace(var.tailscale_client_id) != "" ? var.tailscale_client_id : try(local.ephemeral_sops_data.tailscale.client_id, "")
  tailscale_client_secret = var.tailscale_client_secret != null && trimspace(var.tailscale_client_secret) != "" ? var.tailscale_client_secret : try(local.ephemeral_sops_data.tailscale.client_secret, "")
  tailnet_name            = var.tailnet_name != null && trimspace(var.tailnet_name) != "" ? var.tailnet_name : try(local.sops_config.tailnet_name, "")

  # Tailscale tailnet contact emails: read from scoped SOPS config subtree.
  contact_account_email  = try(local.sops_config.contact_account_email, "")
  contact_support_email  = try(local.sops_config.contact_support_email, "")
  contact_security_email = try(local.sops_config.contact_security_email, "")

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
    "tag:type-server"       = ["autogroup:owner"]
    "tag:type-client"       = ["autogroup:owner"]
    "tag:type-nas"          = ["autogroup:owner"]
    "tag:type-network"      = ["autogroup:owner"]
    "tag:type-docker"       = ["autogroup:owner"]
    "tag:os-linux"          = ["autogroup:owner"]
    "tag:os-windows"        = ["autogroup:owner"]
    "tag:os-macos"          = ["autogroup:owner"]
    "tag:os-ios"            = ["autogroup:owner"]
    "tag:os-appletv"        = ["autogroup:owner"]
    "tag:device-desktop"    = ["autogroup:owner"]
    "tag:device-laptop"     = ["autogroup:owner"]
    "tag:device-mobile"     = ["autogroup:owner"]
    "tag:hosting-onpremise" = ["autogroup:owner"]
    "tag:hosting-cloud"     = ["autogroup:owner"]
    "tag:location-us"       = ["autogroup:owner"]
    "tag:location-ger"      = ["autogroup:owner"]
    "tag:env-gcp"           = ["autogroup:owner"]
    "tag:env-aws"           = ["autogroup:owner"]
    "tag:env-oci"           = ["autogroup:owner"]
    "tag:env-cloudflare"    = ["autogroup:owner"]
    "tag:svc-beszel"        = ["autogroup:owner"]
    "tag:svc-node-red"      = ["autogroup:owner"]
    "tag:svc-adguard"       = ["autogroup:owner"]
  }
}

