check "magic_dns_health" {
  assert {
    condition     = tailscale_dns_preferences.homelab.magic_dns == true
    error_message = "Tailscale MagicDNS must remain enabled."
  }
}

check "settings_invariants" {
  assert {
    condition     = tailscale_tailnet_settings.homelab.devices_key_duration_days <= 180
    error_message = "Tailnet device key duration must not exceed 180 days."
  }
  assert {
    condition     = tailscale_tailnet_settings.homelab.users_approval_on == true
    error_message = "Tailnet user approval must remain enforced."
  }
}

check "policy_loaded" {
  assert {
    condition     = length(tailscale_acl.homelab.acl) > 0
    error_message = "Tailscale ACL policy file must not be empty."
  }
}

check "free_tier_invariants" {
  assert {
    condition     = length(local.tag_owners) <= 50
    error_message = "Tailscale Free Tier limit exceeded: tailnet has ${length(local.tag_owners)} tags (maximum allowed is 50)."
  }

  assert {
    condition     = tailscale_tailnet_settings.homelab.posture_identity_collection_on == false
    error_message = "Posture identity collection requires an Enterprise/Standard subscription and must remain false on Always Free tier."
  }

  assert {
    condition     = tailscale_tailnet_settings.homelab.regional_routing_on == false
    error_message = "Regional routing requires a paid subscription ($18/user/mo) and must remain false on Always Free tier."
  }

  assert {
    condition     = tailscale_tailnet_settings.homelab.devices_approval_on == true
    error_message = "Device approval gate must remain enabled for zero-trust security."
  }

  assert {
    condition     = tailscale_tailnet_settings.homelab.acls_externally_managed_on == true
    error_message = "Tailscale ACLs must be externally managed to prevent UI modifications."
  }
}

check "device_discovery_diagnostics" {
  assert {
    condition     = (length(try(data.tailscale_devices.all.devices, [])) == 0 && length(var.device_id_overrides) == 0) || alltrue([for host, dev in var.infrastructure_devices : contains(keys(local.device_id_map), host)])
    error_message = "One or more infrastructure devices defined in var.infrastructure_devices cannot be resolved from tailnet discovery or device_id_overrides."
  }
}
