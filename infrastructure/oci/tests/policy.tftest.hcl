mock_provider "oci" {}
mock_provider "sops" {}

mock_provider "external" {
  override_data {
    target = data.external.sops_config
    values = {
      result = {
        json = "{}"
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
  enable_prevent_destroy      = false
}

# STD-OT-59: Security and Always Free policy invariants that static scanners
# cannot evaluate because they depend on expressions, locals, or cross-resource state.
run "policy_invariants" {
  command = plan

  assert {
    condition = (
      alltrue([for i in oci_core_instance.amd : i.instance_options[0].are_legacy_imds_endpoints_disabled == true]) &&
      oci_core_instance.ampere.instance_options[0].are_legacy_imds_endpoints_disabled == true
    )
    error_message = "IMDSv1 must be disabled on every OCI instance (STD-OT-48, STD-OT-59)."
  }

  assert {
    condition = (
      alltrue([for i in oci_core_instance.amd : i.launch_options[0].is_pv_encryption_in_transit_enabled == true]) &&
      oci_core_instance.ampere.launch_options[0].is_pv_encryption_in_transit_enabled == true
    )
    error_message = "Paravirtualized in-transit encryption must be enabled on every OCI instance (STD-OT-48, STD-OT-59)."
  }

  assert {
    condition = (
      alltrue([for i in oci_core_instance.amd : i.create_vnic_details[0].assign_public_ip == "false"]) &&
      oci_core_instance.ampere.create_vnic_details[0].assign_public_ip == "false" &&
      oci_core_subnet.private.prohibit_public_ip_on_vnic == true
    )
    error_message = "Public IPv4 assignment must be prohibited on all OCI VNICs and subnets (STD-OT-48, STD-OT-59)."
  }

  assert {
    condition = (
      oci_core_network_security_group_security_rule.ingress_admin_ssh.source != "0.0.0.0/0" &&
      alltrue([for r in oci_core_security_list.private.ingress_security_rules : r.protocol == "1" && r.source != "0.0.0.0/0"])
    )
    error_message = "SSH ingress must never allow 0.0.0.0/0 and private security list ingress must stay restricted to PMTUD ICMP (STD-OT-48, STD-OT-59)."
  }

  assert {
    condition     = length(oci_core_security_list.private.egress_security_rules) == 0
    error_message = "Private security list must not define egress_security_rules so VNIC egress is governed exclusively by the NSG allow-list (R2-TF-05, STD-OT-48)."
  }

  assert {
    condition = (
      oci_core_network_security_group_security_rule.egress_tailscale_stun.direction == "EGRESS" &&
      oci_core_network_security_group_security_rule.egress_tailscale_stun.protocol == "17" &&
      oci_core_network_security_group_security_rule.egress_tailscale_stun.destination == "0.0.0.0/0" &&
      oci_core_network_security_group_security_rule.egress_tailscale_stun.udp_options[0].destination_port_range[0].min == 3478 &&
      oci_core_network_security_group_security_rule.egress_tailscale_stun.udp_options[0].destination_port_range[0].max == 3478
    )
    error_message = "NSG must define egress_tailscale_stun allowing outbound UDP 3478 to 0.0.0.0/0 (R2-TF-05)."
  }

  assert {
    condition = (
      oci_core_network_security_group_security_rule.egress_ntp.direction == "EGRESS" &&
      oci_core_network_security_group_security_rule.egress_ntp.protocol == "17" &&
      oci_core_network_security_group_security_rule.egress_ntp.destination == "0.0.0.0/0" &&
      oci_core_network_security_group_security_rule.egress_ntp.udp_options[0].destination_port_range[0].min == 123 &&
      oci_core_network_security_group_security_rule.egress_ntp.udp_options[0].destination_port_range[0].max == 123
    )
    error_message = "NSG must define egress_ntp allowing outbound UDP 123 to 0.0.0.0/0 (R2-TF-05)."
  }

  assert {
    condition = (
      oci_core_network_security_group_security_rule.egress_http.direction == "EGRESS" &&
      oci_core_network_security_group_security_rule.egress_http.protocol == "6" &&
      oci_core_network_security_group_security_rule.egress_http.destination == "0.0.0.0/0" &&
      oci_core_network_security_group_security_rule.egress_http.tcp_options[0].destination_port_range[0].min == 80 &&
      oci_core_network_security_group_security_rule.egress_http.tcp_options[0].destination_port_range[0].max == 80
    )
    error_message = "NSG must define egress_http allowing outbound TCP 80 to 0.0.0.0/0 (R2-TF-05)."
  }

  assert {
    condition = toset([
      oci_core_network_security_group_security_rule.egress_https.tcp_options[0].destination_port_range[0].min,
      oci_core_network_security_group_security_rule.egress_dns_udp.udp_options[0].destination_port_range[0].min,
      oci_core_network_security_group_security_rule.egress_dns_tcp.tcp_options[0].destination_port_range[0].min,
      oci_core_network_security_group_security_rule.egress_tailscale_wireguard.udp_options[0].destination_port_range[0].min,
      oci_core_network_security_group_security_rule.egress_tailscale_stun.udp_options[0].destination_port_range[0].min,
      oci_core_network_security_group_security_rule.egress_ntp.udp_options[0].destination_port_range[0].min,
      oci_core_network_security_group_security_rule.egress_http.tcp_options[0].destination_port_range[0].min,
    ]) == toset([443, 53, 41641, 3478, 123, 80])
    error_message = "NSG egress destination port set must equal {443, 53, 41641, 3478, 123, 80} (R2-TF-05)."
  }

  assert {
    condition = (
      alltrue([
        for i in oci_core_instance.amd :
        strcontains(base64decode(i.metadata["user_data"]), "--auth-key=file:/run/ts.key") &&
        strcontains(base64decode(i.metadata["user_data"]), "shred -u /run/ts.key") &&
        !strcontains(base64decode(i.metadata["user_data"]), "--authkey=")
      ]) &&
      strcontains(base64decode(oci_core_instance.ampere.metadata["user_data"]), "--auth-key=file:/run/ts.key") &&
      strcontains(base64decode(oci_core_instance.ampere.metadata["user_data"]), "shred -u /run/ts.key") &&
      !strcontains(base64decode(oci_core_instance.ampere.metadata["user_data"]), "--authkey=")
    )
    error_message = "Cloud-init user_data must deliver Tailscale auth key via /run/ts.key and shred it after use (STD-OT-48, STD-OT-59)."
  }

  assert {
    condition = (
      length(oci_core_instance.amd) <= 2 &&
      alltrue([for i in oci_core_instance.amd : i.shape == "VM.Standard.E2.1.Micro"]) &&
      oci_core_instance.ampere.shape == "VM.Standard.A1.Flex" &&
      oci_core_instance.ampere.shape_config[0].ocpus <= 4 &&
      oci_core_instance.ampere.shape_config[0].memory_in_gbs <= 24 &&
      (2 * var.amd_boot_volume_size_gb + var.arm_boot_volume_size_gb) <= 200 &&
      oci_budget_budget.zero_spend.amount <= 1
    )
    error_message = "OCI compute, storage, and budget must remain within Always Free ceilings (STD-OT-39, STD-OT-59)."
  }

  assert {
    condition = (
      oci_objectstorage_bucket.backups.access_type == "NoPublicAccess" &&
      oci_objectstorage_bucket.backups.versioning == "Disabled" &&
      alltrue([for s in oci_identity_policy.backup_uploaders.statements : !strcontains(s, "OBJECT_DELETE")])
    )
    error_message = "OCI backup bucket must block public access, keep versioning disabled, and enforce append-only IAM without OBJECT_DELETE (STD-OT-51, STD-OT-59)."
  }

  assert {
    condition = (
      alltrue([for i in oci_core_instance.amd : i.freeform_tags["project"] == "homelab"]) &&
      oci_core_instance.ampere.freeform_tags["project"] == "homelab" &&
      oci_core_vcn.main.freeform_tags["project"] == "homelab" &&
      oci_core_subnet.private.freeform_tags["project"] == "homelab" &&
      oci_core_network_security_group.homelab.freeform_tags["project"] == "homelab" &&
      oci_objectstorage_bucket.backups.freeform_tags["project"] == "homelab" &&
      oci_budget_budget.zero_spend.freeform_tags["project"] == "homelab"
    )
    error_message = "All taggable OCI resources must carry freeform_tags[\"project\"] == \"homelab\" (STD-OT-37, STD-OT-59)."
  }
}
