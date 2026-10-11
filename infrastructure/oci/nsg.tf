# --- Network Security Group (NSG) Hardening ---

resource "oci_core_network_security_group" "homelab" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "homelab-nsg"
  freeform_tags  = local.effective_tags
}

# --- Ingress Rules ---

# Direct WireGuard for Tailscale peer-to-peer connectivity
resource "oci_core_network_security_group_security_rule" "ingress_tailscale_wireguard" {
  #checkov:skip=CKV_OCI_21:Stateful connection tracking is intentionally required for bidirectional ingress and automatic response traffic
  network_security_group_id = oci_core_network_security_group.homelab.id
  direction                 = "INGRESS"
  protocol                  = "17" # UDP
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  description               = "Allow inbound Tailscale Direct WireGuard traffic"

  udp_options {
    destination_port_range {
      min = 41641
      max = 41641
    }
  }
}

# Restricted SSH access strictly from authorized admin CIDR (never 0.0.0.0/0)
resource "oci_core_network_security_group_security_rule" "ingress_admin_ssh" {
  #checkov:skip=CKV_OCI_21:Stateful connection tracking is intentionally required for bidirectional ingress and automatic response traffic
  network_security_group_id = oci_core_network_security_group.homelab.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = local.admin_cidr
  source_type               = "CIDR_BLOCK"
  description               = "Restricted SSH access from authorized admin CIDR"

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

# --- Egress Rules ---

# Outbound HTTPS for package repositories and APIs
resource "oci_core_network_security_group_security_rule" "egress_https" {
  network_security_group_id = oci_core_network_security_group.homelab.id
  direction                 = "EGRESS"
  protocol                  = "6" # TCP
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "Allow outbound HTTPS traffic"

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

# Outbound DNS (UDP)
resource "oci_core_network_security_group_security_rule" "egress_dns_udp" {
  network_security_group_id = oci_core_network_security_group.homelab.id
  direction                 = "EGRESS"
  protocol                  = "17" # UDP
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "Allow outbound DNS UDP traffic"

  udp_options {
    destination_port_range {
      min = 53
      max = 53
    }
  }
}

# Outbound DNS (TCP)
resource "oci_core_network_security_group_security_rule" "egress_dns_tcp" {
  network_security_group_id = oci_core_network_security_group.homelab.id
  direction                 = "EGRESS"
  protocol                  = "6" # TCP
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "Allow outbound DNS TCP traffic"

  tcp_options {
    destination_port_range {
      min = 53
      max = 53
    }
  }
}

# Outbound WireGuard for Tailscale
resource "oci_core_network_security_group_security_rule" "egress_tailscale_wireguard" {
  network_security_group_id = oci_core_network_security_group.homelab.id
  direction                 = "EGRESS"
  protocol                  = "17" # UDP
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "Allow outbound Tailscale Direct WireGuard traffic"

  udp_options {
    destination_port_range {
      min = 41641
      max = 41641
    }
  }
}
