# --- Networking (VCN, Private Subnet, NAT Gateway, Route Table) ---

resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "homelab-vcn"
  dns_label      = "homelab"
  freeform_tags  = local.effective_tags
}

resource "oci_core_nat_gateway" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "homelab-nat-gateway"
  freeform_tags  = local.effective_tags
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "homelab-private-rt"
  freeform_tags  = local.effective_tags

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
  freeform_tags  = local.effective_tags

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
    description = "Allow all outbound internet traffic via NAT gateway"
  }

  # Dropped broad VCN-wide allow-all ingress rule in favor of granular NSGs on instance VNICs.
  # ICMP type 3 code 4 is retained for Path MTU Discovery (PMTUD).
  ingress_security_rules {
    protocol    = "1"
    source      = var.vcn_cidr
    description = "Allow ICMP Destination Unreachable Fragmentation Needed for PMTUD"

    icmp_options {
      type = 3
      code = 4
    }
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
  freeform_tags              = local.effective_tags
}
