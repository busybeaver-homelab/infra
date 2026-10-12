mock_provider "tailscale" {}

mock_provider "sops" {
  override_data {
    target = data.sops_file.secrets
    values = {
      raw = <<-EOT
        tailscale:
          client_id: "ts-client-id-decoy"
          client_secret: "ts-client-secret-decoy"
          config:
            tailnet_name: "example.ts.net"
            contact_account_email: "account@example.test"
            contact_support_email: "support@example.test"
            contact_security_email: "security@example.test"
      EOT
    }
  }
}

variables {
  policy_file_path = "policy.ci.hujson"
}

run "unit_plan_matches_baseline" {
  command = plan

  assert {
    condition     = tailscale_dns_preferences.homelab.magic_dns == true
    error_message = "MagicDNS should be enabled."
  }

  assert {
    condition     = tailscale_tailnet_settings.homelab.devices_approval_on == false
    error_message = "Device approval should be false."
  }

  assert {
    condition     = tailscale_tailnet_settings.homelab.devices_auto_updates_on == true
    error_message = "Device auto-updates should be enabled."
  }

  assert {
    condition     = tailscale_tailnet_settings.homelab.devices_key_duration_days == 90
    error_message = "Key duration days must be 90."
  }

  assert {
    condition     = tailscale_tailnet_settings.homelab.users_approval_on == true
    error_message = "User approval must be true."
  }

  assert {
    condition     = tailscale_tailnet_settings.homelab.https_enabled == true
    error_message = "HTTPS must be enabled."
  }

  assert {
    condition     = tailscale_tailnet_settings.homelab.users_role_allowed_to_join_external_tailnet == "admin"
    error_message = "Role allowed to join external tailnet must be admin."
  }

  assert {
    condition     = one(tailscale_contacts.homelab.account).email == "account@example.test"
    error_message = "Contact account email did not match decoy."
  }

  assert {
    condition     = one(tailscale_contacts.homelab.support).email == "support@example.test"
    error_message = "Contact support email did not match decoy."
  }

  assert {
    condition     = one(tailscale_contacts.homelab.security).email == "security@example.test"
    error_message = "Contact security email did not match decoy."
  }

  assert {
    condition     = tailscale_tailnet_key.bootstrap.preauthorized == true
    error_message = "Bootstrap key must be preauthorized."
  }

  assert {
    condition     = tailscale_tailnet_key.bootstrap.reusable == true
    error_message = "Bootstrap key must be reusable."
  }

  assert {
    condition     = tailscale_tailnet_key.bootstrap.ephemeral == false
    error_message = "Bootstrap key must not be ephemeral."
  }

  assert {
    condition     = length(tailscale_acl.homelab.acl) > 0
    error_message = "Tailscale ACL policy file must not be empty."
  }
}

run "verify_computed_outputs_on_apply" {
  command = apply

  assert {
    condition     = output.devices != null
    error_message = "Devices output should not be null."
  }

  assert {
    condition     = output.auth_key_bootstrap != ""
    error_message = "Auth key bootstrap output must not be empty."
  }
}
