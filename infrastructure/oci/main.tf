# --- Encrypted Secrets Integration (SOPS) ---

data "sops_file" "secrets" {
  source_file = var.secrets_file_path
}

# --- Budget & Spend Monitoring ---

resource "oci_budget_budget" "zero_spend" {
  compartment_id = var.tenancy_ocid
  amount         = var.budget_amount
  reset_period   = "MONTHLY"
  target_type    = "COMPARTMENT"
  targets        = [var.compartment_ocid]
  display_name   = "zero-spend-monthly-budget"
  description    = "Enforce zero/minimal spend limit for Always Free resources"
  freeform_tags  = var.default_freeform_tags
}

resource "oci_budget_alert_rule" "threshold_alert" {
  budget_id      = oci_budget_budget.zero_spend.id
  threshold      = var.budget_alert_threshold
  threshold_type = "PERCENTAGE"
  type           = "ACTUAL"
  recipients     = var.budget_alert_recipients
  display_name   = "budget-100-percent-alert"
  message        = "Warning: OCI Free Tier spending has reached 100% of the $1 threshold!"
}

# --- Networking (VCN, Private Subnet, NAT Gateway) ---

resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "homelab-vcn"
  dns_label      = "homelab"
  freeform_tags  = var.default_freeform_tags
}

resource "oci_core_nat_gateway" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "homelab-nat-gateway"
  freeform_tags  = var.default_freeform_tags
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "homelab-private-rt"
  freeform_tags  = var.default_freeform_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.main.id
    description       = "Outbound internet traffic routed to NAT gateway"
  }
}

resource "oci_core_security_list" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "homelab-private-sl"
  freeform_tags  = var.default_freeform_tags

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
    description = "Allow all outbound internet traffic via NAT gateway"
  }

  ingress_security_rules {
    protocol    = "all"
    source      = var.vcn_cidr
    description = "Allow all internal traffic within the VCN"
  }
}

resource "oci_core_subnet" "private" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.subnet_cidr
  display_name               = "homelab-private-subnet"
  dns_label                  = "private"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.private.id]
  freeform_tags              = var.default_freeform_tags
}

# --- Compute Instances (Always Free Tier) ---

locals {
  tailscale_tags     = join(",", concat(var.tailscale_common_tags, var.tailscale_extra_tags_oci))
  tailscale_auth_key = coalesce(var.tailscale_auth_key != "" ? var.tailscale_auth_key : null, try(data.sops_file.secrets.data["oci.tailscale_auth_key"], ""))
}

# 2x AMD Compute Instances (VM.Standard.E2.1.Micro)
resource "oci_core_instance" "amd" {
  count               = 2
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = "oci-amd-${count.index + 1}"
  shape               = "VM.Standard.E2.1.Micro"
  freeform_tags       = var.default_freeform_tags

  create_vnic_details {
    subnet_id        = oci_core_subnet.private.id
    assign_public_ip = false
    display_name     = "oci-amd-${count.index + 1}-vnic"
    hostname_label   = "oci-amd-${count.index + 1}"
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
}

# 1x Ampere A1 Compute Instance (VM.Standard.A1.Flex - 4 OCPUs, 24GB RAM)
resource "oci_core_instance" "ampere" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = "oci-arm-1"
  shape               = "VM.Standard.A1.Flex"
  freeform_tags       = var.default_freeform_tags

  shape_config {
    ocpus         = 4
    memory_in_gbs = 24
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.private.id
    assign_public_ip = false
    display_name     = "oci-arm-1-vnic"
    hostname_label   = "oci-arm-1"
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
}

# --- Object Storage Bucket for Encrypted Backups (Always Free Tier) ---

data "oci_objectstorage_namespace" "main" {
  compartment_id = var.compartment_ocid
}

resource "oci_objectstorage_bucket" "backups" {
  compartment_id = var.compartment_ocid
  name           = "homelab-backups-${var.tenancy_name}"
  namespace      = data.oci_objectstorage_namespace.main.namespace
  storage_tier   = "Standard"
  access_type    = "NoPublicAccess"
  versioning     = "Disabled"

  freeform_tags = merge(var.default_freeform_tags, {
    "Environment" = "Production"
    "Role"        = "Backup"
  })
}


