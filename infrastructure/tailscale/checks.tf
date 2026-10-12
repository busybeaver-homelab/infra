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
