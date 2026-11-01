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

run "unit_plan_matches_baseline" {
  command = plan

  assert {
    condition     = tailscale_dns_preferences.homelab.magic_dns == true
    error_message = "MagicDNS should be enabled."
  }

  assert {
    condition     = tailscale_tailnet_settings.homelab.devices_approval_on == true
    error_message = "Device approval should be true."
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
    condition     = alltrue([for owners in values(local.tag_owners) : owners == ["autogroup:owner"]])
    error_message = "Every tag in local.tag_owners must be owned exclusively by autogroup:owner."
  }

  assert {
    condition     = length(tailscale_acl.homelab.acl) > 0
    error_message = "Tailscale ACL policy file must not be empty."
  }

  assert {
    condition     = strcontains(tailscale_acl.homelab.acl, "nextdns:000000")
    error_message = "Tailscale ACL policy must include NextDNS decoy attribute in nodeAttrs."
  }

  assert {
    condition     = strcontains(tailscale_acl.homelab.acl, "tag:decoy-client")
    error_message = "Tailscale ACL policy must include decoy client target in nodeAttrs."
  }

  assert {
    condition     = strcontains(tailscale_acl.homelab.acl, "\"checkPeriod\": \"12h\"")
    error_message = "Tailscale ACL SSH check rules must enforce a 12h checkPeriod."
  }
}

run "robot_auth_key_is_single_use_and_tagged" {
  command = plan

  assert {
    condition     = tailscale_tailnet_key.robot.tags == toset(["tag:type-iot"])
    error_message = "Robot auth key must carry exactly tag:type-iot."
  }

  assert {
    condition     = tailscale_tailnet_key.robot.reusable == false
    error_message = "Robot auth key must be single-use (reusable = false)."
  }

  assert {
    condition     = tailscale_tailnet_key.robot.ephemeral == false
    error_message = "Robot auth key must not be ephemeral."
  }

  assert {
    condition     = tailscale_tailnet_key.robot.preauthorized == true
    error_message = "Robot auth key must be preauthorized."
  }

  assert {
    condition     = tailscale_tailnet_key.robot.expiry == 3600
    error_message = "Robot auth key expiry must default to 3600 seconds."
  }

  assert {
    condition     = tailscale_tailnet_key.robot.recreate_if_invalid == "never"
    error_message = "Robot auth key must never be recreated automatically (recreate_if_invalid = never)."
  }
}

run "verify_computed_outputs_on_apply" {
  command = apply

  assert {
    condition     = output.devices != null
    error_message = "Devices output should not be null."
  }
}
