mock_provider "oci" {}
mock_provider "sops" {}
mock_provider "tailscale" {
  override_resource {
    target = tailscale_tailnet_key.bootstrap_amd[0]
    values = {
      id  = "mock-ts-key-id-amd-0"
      key = "tskey-auth-mock-amd-0"
    }
  }
  override_resource {
    target = tailscale_tailnet_key.bootstrap_amd[1]
    values = {
      id  = "mock-ts-key-id-amd-1"
      key = "tskey-auth-mock-amd-1"
    }
  }
  override_resource {
    target = tailscale_tailnet_key.bootstrap_ampere
    values = {
      id  = "mock-ts-key-id-ampere"
      key = "tskey-auth-mock-ampere"
    }
  }
}

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

run "verify_compute_instances_and_free_tier" {
  command = plan

  assert {
    condition     = length(oci_core_instance.amd) == 2
    error_message = "Must configure exactly 2 AMD micro instances"
  }

  assert {
    condition     = length(tailscale_tailnet_key.bootstrap_amd) == length(oci_core_instance.amd)
    error_message = "AMD Tailscale bootstrap key count must equal AMD instance count (R2-TF-04)"
  }

  assert {
    condition = (
      alltrue([
        for k in tailscale_tailnet_key.bootstrap_amd :
        k.reusable == false &&
        k.ephemeral == false &&
        k.preauthorized == true &&
        k.expiry <= 3600 &&
        k.recreate_if_invalid == "never"
      ]) &&
      tailscale_tailnet_key.bootstrap_ampere.reusable == false &&
      tailscale_tailnet_key.bootstrap_ampere.ephemeral == false &&
      tailscale_tailnet_key.bootstrap_ampere.preauthorized == true &&
      tailscale_tailnet_key.bootstrap_ampere.expiry <= 3600 &&
      tailscale_tailnet_key.bootstrap_ampere.recreate_if_invalid == "never"
    )
    error_message = "Every OCI Tailscale bootstrap key must be single-use (!reusable), non-ephemeral, preauthorized, expire within 3600s, and set recreate_if_invalid == \"never\" (R2-TF-04)"
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
    condition     = oci_core_instance.ampere.shape_config[0].ocpus <= 2
    error_message = "ARM instance OCPUs must not exceed 2 (Always Free limit)"
  }

  assert {
    condition     = oci_core_instance.ampere.shape_config[0].memory_in_gbs <= 12
    error_message = "ARM instance memory must not exceed 12 GB (Always Free limit)"
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

  assert {
    condition     = oci_core_instance.amd[0].launch_options[0].is_pv_encryption_in_transit_enabled == true
    error_message = "AMD instance must have in-transit encryption enabled on launch options"
  }

  assert {
    condition     = oci_core_instance.ampere.launch_options[0].is_pv_encryption_in_transit_enabled == true
    error_message = "ARM instance must have in-transit encryption enabled on launch options"
  }
}

run "verify_computed_outputs_on_apply" {
  command = apply

  assert {
    condition     = strcontains(base64decode(oci_core_instance.amd[0].metadata["user_data"]), "--hostname=\"oci-amd-1\"")
    error_message = "AMD instance user_data must render shared cloud-init template with hostname oci-amd-1"
  }

  assert {
    condition     = strcontains(base64decode(oci_core_instance.amd[0].metadata["user_data"]), "--auth-key=file:/run/ts.key") && strcontains(base64decode(oci_core_instance.amd[0].metadata["user_data"]), "shred -u /run/ts.key") && !strcontains(base64decode(oci_core_instance.amd[0].metadata["user_data"]), "--authkey=")
    error_message = "AMD instance user_data must deliver Tailscale auth key via /run/ts.key and shred it after use"
  }

  assert {
    condition     = strcontains(base64decode(oci_core_instance.ampere.metadata["user_data"]), "--hostname=\"oci-arm-1\"")
    error_message = "ARM instance user_data must render shared cloud-init template with hostname oci-arm-1"
  }

  assert {
    condition = (
      strcontains(base64decode(oci_core_instance.amd[0].metadata["user_data"]), "content: \"${tailscale_tailnet_key.bootstrap_amd[0].key}\"") &&
      !strcontains(base64decode(oci_core_instance.amd[0].metadata["user_data"]), "content: \"${tailscale_tailnet_key.bootstrap_amd[1].key}\"") &&
      !strcontains(base64decode(oci_core_instance.amd[0].metadata["user_data"]), "content: \"${tailscale_tailnet_key.bootstrap_ampere.key}\"") &&
      strcontains(base64decode(oci_core_instance.amd[1].metadata["user_data"]), "content: \"${tailscale_tailnet_key.bootstrap_amd[1].key}\"") &&
      !strcontains(base64decode(oci_core_instance.amd[1].metadata["user_data"]), "content: \"${tailscale_tailnet_key.bootstrap_amd[0].key}\"") &&
      !strcontains(base64decode(oci_core_instance.amd[1].metadata["user_data"]), "content: \"${tailscale_tailnet_key.bootstrap_ampere.key}\"") &&
      strcontains(base64decode(oci_core_instance.ampere.metadata["user_data"]), "content: \"${tailscale_tailnet_key.bootstrap_ampere.key}\"") &&
      !strcontains(base64decode(oci_core_instance.ampere.metadata["user_data"]), "content: \"${tailscale_tailnet_key.bootstrap_amd[0].key}\"") &&
      !strcontains(base64decode(oci_core_instance.ampere.metadata["user_data"]), "content: \"${tailscale_tailnet_key.bootstrap_amd[1].key}\"")
    )
    error_message = "Each OCI instance user_data must hold its own dedicated single-use Tailscale bootstrap key only (R2-TF-04)"
  }

  assert {
    condition = (
      !strcontains(
        templatefile("${path.module}/../modules/cloud-init/cloud-init.yaml.tftpl", {
          hostname                 = "test-empty"
          breakglass_user          = "testadmin"
          breakglass_password_hash = "$6$rounds=4096$testsalt$testhash"
          ssh_public_key           = ""
          tailscale_auth_key       = ""
          tailscale_client_id      = ""
          tailscale_audience       = ""
          tailscale_tags           = ""
        }),
        "tailscale up"
      ) &&
      !strcontains(
        templatefile("${path.module}/../modules/cloud-init/cloud-init.yaml.tftpl", {
          hostname                 = "test-empty"
          breakglass_user          = "testadmin"
          breakglass_password_hash = "$6$rounds=4096$testsalt$testhash"
          ssh_public_key           = ""
          tailscale_auth_key       = ""
          tailscale_client_id      = ""
          tailscale_audience       = ""
          tailscale_tags           = ""
        }),
        "shred"
      )
    )
    error_message = "cloud-init template with empty tailscale_auth_key and empty tailscale_client_id must render no tailscale up and no shred commands (R2-TF-04)"
  }

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

  assert {
    condition = (
      toset(keys(output.ansible_inventory)) == toset(["oci-amd-1", "oci-amd-2", "oci-arm-1"]) &&
      output.ansible_inventory["oci-amd-1"].group == "oci" &&
      output.ansible_inventory["oci-arm-1"].group == "oci" &&
      output.ansible_inventory["oci-amd-1"].ansible_host == "oci-amd-1" &&
      output.ansible_inventory["oci-arm-1"].ansible_host == "oci-arm-1"
    )
    error_message = "ansible_inventory output must expose all three OCI compute instances with group=oci"
  }
}

