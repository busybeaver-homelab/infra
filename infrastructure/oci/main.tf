# --- Encrypted Secrets Integration (SOPS) ---

ephemeral "sops_file" "secrets" {
  source_file = var.secrets_file_path
}

data "external" "sops_config" {
  program = ["bash", "${path.module}/../../scripts/sops-subtree.sh"]
  query = {
    file    = var.secrets_file_path
    extract = "[\"oci\"][\"config\"]"
  }
}

data "external" "sops_tailscale_auth_key" {
  program = ["bash", "${path.module}/../../scripts/sops-subtree.sh"]
  query = {
    file    = var.secrets_file_path
    extract = "[\"oci\"][\"tailscale_auth_key\"]"
  }
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

  launch_options {
    boot_volume_type                    = "PARAVIRTUALIZED"
    network_type                        = "PARAVIRTUALIZED"
    is_pv_encryption_in_transit_enabled = true
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.private.id
    assign_public_ip = var.assign_public_ip
    display_name     = "oci-amd-${count.index + 1}-vnic"
    hostname_label   = "oci-amd-${count.index + 1}"
    nsg_ids          = [oci_core_network_security_group.homelab.id]
  }

  source_details {
    source_type             = "image"
    source_id               = var.instance_image_ocid_amd
    boot_volume_size_in_gbs = var.amd_boot_volume_size_gb
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/../modules/cloud-init/cloud-init.yaml.tftpl", {
      tailscale_auth_key = local.tailscale_auth_key
      hostname           = "oci-amd-${count.index + 1}"
      tailscale_tags     = local.tailscale_tags
    }))
  }

  lifecycle {
    prevent_destroy = var.enable_prevent_destroy

    precondition {
      condition     = 2 * var.amd_boot_volume_size_gb + var.arm_boot_volume_size_gb <= 200
      error_message = "Combined OCI boot volume storage across all instances must not exceed the 200 GB Always Free limit."
    }

    ignore_changes = [
      metadata["user_data"],
      metadata["ssh_authorized_keys"],
      source_details[0].source_id,
      defined_tags["Oracle-Tags.CreatedBy"],
      defined_tags["Oracle-Tags.CreatedOn"],
    ]
  }
}

# 1x Ampere A1 Compute Instance (VM.Standard.A1.Flex - 2 OCPUs, 12GB RAM: the full Always Free A1 allowance)
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

  launch_options {
    boot_volume_type                    = "PARAVIRTUALIZED"
    network_type                        = "PARAVIRTUALIZED"
    is_pv_encryption_in_transit_enabled = true
  }

  shape_config {
    ocpus         = var.ampere_ocpus
    memory_in_gbs = var.ampere_memory_in_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.private.id
    assign_public_ip = var.assign_public_ip
    display_name     = "oci-arm-1-vnic"
    hostname_label   = "oci-arm-1"
    nsg_ids          = [oci_core_network_security_group.homelab.id]
  }

  source_details {
    source_type             = "image"
    source_id               = var.instance_image_ocid_arm
    boot_volume_size_in_gbs = var.arm_boot_volume_size_gb
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/../modules/cloud-init/cloud-init.yaml.tftpl", {
      tailscale_auth_key = local.tailscale_auth_key
      hostname           = "oci-arm-1"
      tailscale_tags     = local.tailscale_tags
    }))
  }

  lifecycle {
    prevent_destroy = var.enable_prevent_destroy

    precondition {
      condition     = var.ampere_ocpus <= 2 && var.ampere_memory_in_gbs <= 12
      error_message = "Ampere A1 shape must remain within the Always Free allowance (<= 2 OCPUs, <= 12 GB memory)."
    }

    precondition {
      condition     = 2 * var.amd_boot_volume_size_gb + var.arm_boot_volume_size_gb <= 200
      error_message = "Combined OCI boot volume storage across all instances must not exceed the 200 GB Always Free limit."
    }

    ignore_changes = [
      metadata["user_data"],
      metadata["ssh_authorized_keys"],
      source_details[0].source_id,
      defined_tags["Oracle-Tags.CreatedBy"],
      defined_tags["Oracle-Tags.CreatedOn"],
    ]
  }
}


