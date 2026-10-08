# --- Encrypted Secrets Integration (SOPS) ---

data "sops_file" "secrets" {
  source_file = var.secrets_file_path
}


# --- Compute Instances (Always Free Tier) ---

# 2x AMD Compute Instances (VM.Standard.E2.1.Micro)
resource "oci_core_instance" "amd" {
  count                = 2
  availability_domain  = var.availability_domain
  compartment_id       = var.compartment_ocid
  display_name         = "oci-amd-${count.index + 1}"
  shape                = "VM.Standard.E2.1.Micro"
  preserve_boot_volume = false
  freeform_tags        = local.effective_tags

  instance_options {
    are_legacy_imds_endpoints_disabled = true
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.private.id
    assign_public_ip = false
    display_name     = "oci-amd-${count.index + 1}-vnic"
    hostname_label   = "oci-amd-${count.index + 1}"
    nsg_ids          = [oci_core_network_security_group.homelab.id]
  }

  source_details {
    source_type             = "image"
    source_id               = var.instance_image_ocid_amd
    boot_volume_size_in_gbs = 50
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
      tailscale_auth_key = local.tailscale_auth_key
      hostname           = "oci-amd-${count.index + 1}"
      tailscale_tags     = local.tailscale_tags
    }))
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      metadata["user_data"],
      metadata["ssh_authorized_keys"],
      source_details[0].source_id,
      defined_tags["Oracle-Tags.CreatedBy"],
      defined_tags["Oracle-Tags.CreatedOn"],
    ]
  }
}

# 1x Ampere A1 Compute Instance (VM.Standard.A1.Flex - 4 OCPUs, 24GB RAM)
resource "oci_core_instance" "ampere" {
  availability_domain  = var.availability_domain
  compartment_id       = var.compartment_ocid
  display_name         = "oci-arm-1"
  shape                = "VM.Standard.A1.Flex"
  preserve_boot_volume = false
  freeform_tags        = local.effective_tags

  instance_options {
    are_legacy_imds_endpoints_disabled = true
  }

  shape_config {
    ocpus         = 4
    memory_in_gbs = 24
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.private.id
    assign_public_ip = false
    display_name     = "oci-arm-1-vnic"
    hostname_label   = "oci-arm-1"
    nsg_ids          = [oci_core_network_security_group.homelab.id]
  }

  source_details {
    source_type             = "image"
    source_id               = var.instance_image_ocid_arm
    boot_volume_size_in_gbs = 100
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
      tailscale_auth_key = local.tailscale_auth_key
      hostname           = "oci-arm-1"
      tailscale_tags     = local.tailscale_tags
    }))
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      metadata["user_data"],
      metadata["ssh_authorized_keys"],
      source_details[0].source_id,
      defined_tags["Oracle-Tags.CreatedBy"],
      defined_tags["Oracle-Tags.CreatedOn"],
    ]
  }
}


