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

  # Monitored device hostnames and managed infrastructure devices: use variable override if set, else read from SOPS config.
  monitored_device_hostnames = length(var.monitored_device_hostnames) > 0 ? var.monitored_device_hostnames : [
    for h in try(local.sops_config.monitored_device_hostnames, []) : tostring(h)
  ]

  sops_infrastructure_devices = can(keys(local.sops_config.infrastructure_devices)) ? {
    for k, v in try(local.sops_config.infrastructure_devices, {}) : k => {
      tags                = [for t in v.tags : tostring(t)]
      key_expiry_disabled = try(tobool(v.key_expiry_disabled), true)
      authorized          = try(tobool(v.authorized), true)
    }
    } : {
    for item in try(local.sops_config.infrastructure_devices, []) : tostring(item.hostname) => {
      tags                = [for t in item.tags : tostring(t)]
      key_expiry_disabled = try(tobool(item.key_expiry_disabled), true)
      authorized          = try(tobool(item.authorized), true)
    }
  }

  infrastructure_devices = length(var.infrastructure_devices) > 0 ? var.infrastructure_devices : local.sops_infrastructure_devices

  # Maps hostname (short name before first dot) to node ID
  discovered_device_ids = {
    for d in try(data.tailscale_devices.all.devices, []) :
    split(".", d.name)[0] => d.id
  }

  device_id_map = merge(
    local.discovered_device_ids,
    var.device_id_overrides
  )

  base_tag_owners = {
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
  }

  device_tag_owners = {
    for tag in distinct(flatten([for d in values(local.infrastructure_devices) : d.tags])) :
    tag => ["autogroup:owner"]
  }

  # Single source of truth for tailnet tag ownership (max 50 tags on Always Free Tier)
  tag_owners = merge(
    local.base_tag_owners,
    local.device_tag_owners
  )
}
