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

run "initial_apply" {
  command = apply

  assert {
    condition     = tailscale_dns_preferences.homelab.magic_dns == true
    error_message = "Initial apply must have MagicDNS enabled."
  }

  assert {
    condition     = tailscale_tailnet_key.bootstrap_oci.tags == toset(["tag:type-server", "tag:os-linux", "tag:hosting-cloud", "tag:location-ger", "tag:env-oci"])
    error_message = "Initial apply must retain default bootstrap key tags."
  }

  assert {
    condition     = tailscale_tailnet_key.bootstrap_gcp.tags == toset(["tag:type-server", "tag:os-linux", "tag:hosting-cloud", "tag:location-us", "tag:env-gcp"])
    error_message = "Initial apply must retain default GCP bootstrap key tags."
  }

  assert {
    condition     = tailscale_tailnet_settings.homelab.devices_key_duration_days == 90
    error_message = "Initial apply must set device key duration to 90 days."
  }
}

run "mutate_bootstrap_tags" {
  command = plan

  variables {
    bootstrap_key_tags     = ["tag:type-server", "tag:env-ci"]
    bootstrap_gcp_key_tags = ["tag:type-server", "tag:env-gcp-ci"]
  }

  assert {
    condition     = tailscale_tailnet_key.bootstrap_oci.tags == toset(["tag:type-server", "tag:env-ci"])
    error_message = "Mutated bootstrap tags must reflect in plan."
  }

  assert {
    condition     = tailscale_tailnet_key.bootstrap_oci.reusable == false
    error_message = "Bootstrap key must remain single-use (reusable = false) after tag mutation."
  }

  assert {
    condition     = tailscale_tailnet_key.bootstrap_gcp.tags == toset(["tag:type-server", "tag:env-gcp-ci"])
    error_message = "Mutated GCP bootstrap tags must reflect in plan."
  }

  assert {
    condition     = tailscale_tailnet_key.bootstrap_gcp.reusable == false
    error_message = "GCP bootstrap key must remain single-use (reusable = false) after tag mutation."
  }
}

run "mutate_tailnet_name_override" {
  command = plan

  variables {
    tailnet_name = "custom.example.ts.net"
  }

  assert {
    condition     = var.tailnet_name == "custom.example.ts.net"
    error_message = "Explicit tailnet name variable override must be preserved."
  }
}
