mock_provider "oci" {}
mock_provider "sops" {}
mock_provider "tailscale" {}

mock_provider "external" {
  override_data {
    target = data.external.sops_config
    values = {
      result = {
        json = "{\"budget_alert_recipients\":\"alerts@example.test\"}"
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
  ssh_public_key              = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey user@test"
  enable_prevent_destroy      = false
}

run "initial_apply" {
  command = apply
}

run "mutate_non_destructive_tags" {
  command = plan

  variables {
    default_freeform_tags = {
      project     = "homelab"
      environment = "test-mutation"
    }
  }

  assert {
    condition     = oci_core_instance.amd[0].freeform_tags["environment"] == "test-mutation"
    error_message = "Updated tags must reflect in plan without triggering recreation"
  }

  assert {
    condition     = oci_core_instance.ampere.freeform_tags["environment"] == "test-mutation"
    error_message = "Ampere instance updated tags must reflect in plan without triggering recreation"
  }
}
