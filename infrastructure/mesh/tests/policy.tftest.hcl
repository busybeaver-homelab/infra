mock_provider "tailscale" {}
mock_provider "sops" {}

mock_provider "external" {
  override_data {
    target = data.external.sops_config
    values = {
      result = {
        json = <<-EOT
          {
            "tailnet_name": "example.ts.net",
            "contact_account_email": "account@example.test",
            "contact_support_email": "support@example.test",
            "contact_security_email": "security@example.test"
          }
        EOT
      }
    }
  }
}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
  policy_file_path            = "policy.ci.hujson.tftpl"
}

# STD-OT-59: Zero-trust tailnet posture and Free-Tier tag cap invariants.
run "policy_invariants" {
  command = plan

  assert {
    condition = (
      tailscale_tailnet_settings.homelab.devices_approval_on == true &&
      tailscale_tailnet_settings.homelab.users_approval_on == true &&
      tailscale_tailnet_settings.homelab.devices_auto_updates_on == true &&
      tailscale_tailnet_settings.homelab.https_enabled == true &&
      tailscale_tailnet_settings.homelab.devices_key_duration_days <= 90 &&
      tailscale_tailnet_settings.homelab.users_role_allowed_to_join_external_tailnet == "admin"
    )
    error_message = "Tailscale tailnet settings must enforce device/user approval, auto-updates, HTTPS, <=90d key duration, and admin-only external tailnet join (STD-OT-50, STD-OT-59)."
  }

  assert {
    condition = (
      length(local.tag_owners) <= 50 &&
      alltrue([for owners in values(local.tag_owners) : owners == ["autogroup:owner"]]) &&
      strcontains(tailscale_acl.homelab.acl, "\"checkPeriod\": \"12h\"")
    )
    error_message = "Tailscale ACL tags must remain within the 50-tag Always Free limit, owned solely by autogroup:owner, and enforce a 12h SSH checkPeriod (STD-OT-39, STD-OT-50, STD-OT-59)."
  }
}
