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

run "reject_public_ip_assignment" {
  command = plan

  variables {
    assign_public_ip = true
  }

  expect_failures = [
    var.assign_public_ip,
  ]
}

run "reject_ampere_excessive_ocpus" {
  command = plan

  variables {
    ampere_ocpus = 5
  }

  expect_failures = [
    var.ampere_ocpus,
  ]
}

run "reject_ampere_excessive_memory" {
  command = plan

  variables {
    ampere_memory_in_gbs = 32
  }

  expect_failures = [
    var.ampere_memory_in_gbs,
  ]
}

# Boundary: the Always Free A1 allowance is 2 OCPU / 12 GB (1,500 OCPU-h, 9,000 GB-h per month).
run "reject_ampere_ocpus_just_above_always_free" {
  command = plan

  variables {
    ampere_ocpus = 3
  }

  expect_failures = [
    var.ampere_ocpus,
  ]
}

run "reject_ampere_memory_just_above_always_free" {
  command = plan

  variables {
    ampere_memory_in_gbs = 13
  }

  expect_failures = [
    var.ampere_memory_in_gbs,
  ]
}

run "accept_ampere_at_always_free_limit" {
  command = plan

  variables {
    ampere_ocpus         = 2
    ampere_memory_in_gbs = 12
  }

  assert {
    condition     = oci_core_instance.ampere.shape_config[0].ocpus == 2 && oci_core_instance.ampere.shape_config[0].memory_in_gbs == 12
    error_message = "The Always Free A1 maximum (2 OCPU / 12 GB) must be accepted."
  }
}

run "reject_invalid_project_tag" {
  command = plan

  variables {
    default_freeform_tags = {
      project = "not-homelab"
    }
  }

  expect_failures = [
    var.default_freeform_tags,
  ]
}

run "reject_invalid_tenancy_ocid" {
  command = plan

  variables {
    tenancy_ocid = "not-an-ocid"
  }

  expect_failures = [
    var.tenancy_ocid,
  ]
}

run "reject_invalid_user_ocid" {
  command = plan

  variables {
    user_ocid = "ocid1.wrong.oc1..test"
  }

  expect_failures = [
    var.user_ocid,
  ]
}

run "reject_invalid_fingerprint" {
  command = plan

  variables {
    fingerprint = "invalid:fingerprint:xx"
  }

  expect_failures = [
    var.fingerprint,
  ]
}

run "reject_invalid_compartment_ocid" {
  command = plan

  variables {
    compartment_ocid = "invalid-compartment-ocid"
  }

  expect_failures = [
    var.compartment_ocid,
  ]
}

run "reject_malformed_vcn_cidr" {
  command = plan

  variables {
    vcn_cidr = "999.999.999.999/99"
  }

  expect_failures = [
    var.vcn_cidr,
  ]
}

run "reject_malformed_subnet_cidr" {
  command = plan

  variables {
    subnet_cidr = "999.999.999.999/99"
  }

  expect_failures = [
    var.subnet_cidr,
  ]
}

run "reject_ampere_zero_ocpus" {
  command = plan

  variables {
    ampere_ocpus = 0
  }

  expect_failures = [
    var.ampere_ocpus,
  ]
}

run "reject_ampere_zero_memory" {
  command = plan

  variables {
    ampere_memory_in_gbs = 0
  }

  expect_failures = [
    var.ampere_memory_in_gbs,
  ]
}

run "reject_short_state_encryption_passphrase" {
  command = plan

  variables {
    state_encryption_passphrase = "too-short-test-passphrase"
  }

  expect_failures = [
    var.state_encryption_passphrase,
  ]
}

run "reject_placeholder_state_encryption_passphrase" {
  command = plan

  variables {
    state_encryption_passphrase = "changeme-changeme-changeme-changeme-0001"
  }

  expect_failures = [
    var.state_encryption_passphrase,
  ]
}

run "reject_combined_boot_volume_exceeding_always_free_cap" {
  command = plan

  variables {
    amd_boot_volume_size_gb = 60
    arm_boot_volume_size_gb = 100
  }

  expect_failures = [
    oci_core_instance.amd,
    oci_core_instance.ampere,
  ]
}

run "reject_empty_availability_domain" {
  command = plan

  variables {
    availability_domain = "   "
  }

  expect_failures = [
    var.availability_domain,
  ]
}

run "reject_invalid_instance_image_ocid_amd" {
  command = plan

  variables {
    instance_image_ocid_amd = "not-an-image-ocid"
  }

  expect_failures = [
    var.instance_image_ocid_amd,
  ]
}

run "reject_invalid_instance_image_ocid_arm" {
  command = plan

  variables {
    instance_image_ocid_arm = "not-an-image-ocid"
  }

  expect_failures = [
    var.instance_image_ocid_arm,
  ]
}

run "reject_empty_ssh_public_key" {
  command = plan

  variables {
    ssh_public_key = ""
  }

  expect_failures = [
    var.ssh_public_key,
  ]
}

run "reject_example_domain_budget_recipient" {
  command = plan

  variables {
    budget_alert_recipients = "ops@example.com"
  }

  expect_failures = [
    var.budget_alert_recipients,
  ]
}

run "reject_empty_resolved_budget_alert_recipients" {
  command = plan

  override_data {
    target = data.external.sops_config
    values = {
      result = {
        json = "{}"
      }
    }
  }

  expect_failures = [
    oci_budget_alert_rule.threshold_alert,
    oci_budget_alert_rule.forecast_budget_alert,
  ]
}
