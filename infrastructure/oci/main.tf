# --- Budget & Spend Monitoring ---

resource "oci_budget_budget" "zero_spend" {
  compartment_id = var.tenancy_ocid
  amount         = var.budget_amount
  reset_period   = "MONTHLY"
  target_type    = "COMPARTMENT"
  targets        = [var.compartment_ocid]
  display_name   = "zero-spend-monthly-budget"
  description    = "Enforce zero/minimal spend limit for Always Free resources"
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
}

resource "oci_core_nat_gateway" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "homelab-nat-gateway"
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "homelab-private-rt"

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
}
