mock_provider "oci" {}
mock_provider "sops" {}

mock_provider "external" {
  override_data {
    target = data.external.sops_config
    values = {
      result = {
        json = "{\"budget_alert_recipients\":\"alerts@example.test\"}"
      }
    }
  }

  override_data {
    target = data.external.sops_tailscale_auth_key
    values = {
      result = {
        json = "\"tskey-auth-oci-decoy\""
      }
    }
  }
}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
  tenancy_ocid                = "ocid1.tenancy.oc1..test"
  user_ocid                   = "ocid1.user.oc1..test"
  fingerprint                 = "00:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff"
  private_key                 = "mock-private-key-test-string"
  compartment_ocid            = "ocid1.compartment.oc1..test"
  vcn_cidr                    = "198.51.100.0/24"
  subnet_cidr                 = "198.51.100.0/28"
  admin_cidr                  = "203.0.113.0/24"
  tenancy_name                = "testtenancy"
  availability_domain         = "test-ad"
  instance_image_ocid_amd     = "ocid1.image.oc1..amd"
  instance_image_ocid_arm     = "ocid1.image.oc1..arm"
  tailscale_auth_key          = "tskey-auth-test"
  ssh_public_key              = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey user@test"
}

run "verify_forecast_budget_alert" {
  command = plan

  assert {
    condition     = oci_budget_alert_rule.forecast_budget_alert.type == "FORECAST"
    error_message = "Budget alert must be of type FORECAST"
  }

  assert {
    condition     = oci_budget_alert_rule.forecast_budget_alert.threshold == 100
    error_message = "Budget alert threshold must be 100 percent"
  }

  assert {
    condition     = oci_ons_notification_topic.budget_alerts.name == "homelab-budget-alerts"
    error_message = "Budget alerts notification topic must be named homelab-budget-alerts"
  }
}
