mock_provider "oci" {}
mock_provider "sops" {}

variables {
  tenancy_ocid            = "ocid1.tenancy.oc1..test"
  user_ocid               = "ocid1.user.oc1..test"
  fingerprint             = "00:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff"
  private_key             = "mock-private-key-test-string"
  compartment_ocid        = "ocid1.compartment.oc1..test"
  vcn_cidr                = "198.51.100.0/24"
  subnet_cidr             = "198.51.100.0/28"
  admin_cidr              = "203.0.113.0/24"
  tenancy_name            = "testtenancy"
  availability_domain     = "test-ad"
  instance_image_ocid_amd = "ocid1.image.oc1..amd"
  instance_image_ocid_arm = "ocid1.image.oc1..arm"
  tailscale_auth_key      = "tskey-auth-test"
  ssh_public_key          = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey user@test"
  enable_prevent_destroy  = false
}

run "verify_compute_instances_and_free_tier" {
  command = plan

  assert {
    condition     = length(oci_core_instance.amd) == 2
    error_message = "Must configure exactly 2 AMD micro instances"
  }

  assert {
    condition     = oci_core_instance.amd[0].shape == "VM.Standard.E2.1.Micro"
    error_message = "AMD instance shape must be VM.Standard.E2.1.Micro"
  }

  assert {
    condition     = oci_core_instance.amd[0].create_vnic_details[0].assign_public_ip == "false"
    error_message = "AMD instances must not have public IPs assigned"
  }

  assert {
    condition     = oci_core_instance.amd[0].freeform_tags["project"] == "homelab"
    error_message = "AMD instance must have project=homelab tag"
  }

  assert {
    condition     = oci_core_instance.ampere.shape == "VM.Standard.A1.Flex"
    error_message = "ARM instance shape must be VM.Standard.A1.Flex"
  }

  assert {
    condition     = oci_core_instance.ampere.shape_config[0].ocpus <= 4
    error_message = "ARM instance OCPUs must not exceed 4 (Always Free limit)"
  }

  assert {
    condition     = oci_core_instance.ampere.shape_config[0].memory_in_gbs <= 24
    error_message = "ARM instance memory must not exceed 24 GB (Always Free limit)"
  }

  assert {
    condition     = oci_core_instance.ampere.create_vnic_details[0].assign_public_ip == "false"
    error_message = "ARM instance must not have public IP assigned"
  }

  assert {
    condition     = oci_core_instance.ampere.freeform_tags["project"] == "homelab"
    error_message = "ARM instance must have project=homelab tag"
  }

  assert {
    condition     = oci_core_subnet.private.prohibit_public_ip_on_vnic == true
    error_message = "Private subnet must prohibit public IP assignment"
  }
}

run "verify_computed_outputs_on_apply" {
  command = apply

  assert {
    condition     = output.vcn_id != ""
    error_message = "VCN output ID must be computed upon apply"
  }

  assert {
    condition     = length(output.amd_instance_ids) == 2
    error_message = "Must output exactly 2 AMD instance IDs"
  }

  assert {
    condition     = output.arm_instance_id != ""
    error_message = "ARM instance ID must be computed upon apply"
  }
}

