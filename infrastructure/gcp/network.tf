# --- Networking (VPC, Private Subnet, Restrictive Firewall Rules) ---

resource "google_compute_network" "default_vpc" {
  name                    = "homelab-vpc"
  auto_create_subnetworks = false
  project                 = var.gcp_project_id
}

resource "google_compute_subnetwork" "private" {
  #checkov:skip=CKV_GCP_26:VPC Flow Logs incur billable telemetry charges outside the Always Free Tier
  name                     = "homelab-gcp-subnet"
  ip_cidr_range            = local.vpc_subnet_cidr
  region                   = var.gcp_region
  network                  = google_compute_network.default_vpc.id
  private_ip_google_access = true
  project                  = var.gcp_project_id
}

# Allow inbound Tailscale WireGuard UDP 41641 for direct peer-to-peer mesh tunnels
resource "google_compute_firewall" "allow_tailscale_ingress" {
  name          = "homelab-allow-tailscale-udp"
  network       = google_compute_network.default_vpc.name
  project       = var.gcp_project_id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["homelab-gcp-vm"]

  allow {
    protocol = "udp"
    ports    = ["41641"]
  }
}

# Allow internal VPC ICMP for Path MTU Discovery (PMTUD)
resource "google_compute_firewall" "allow_icmp_pmtud" {
  name          = "homelab-allow-icmp-pmtud"
  network       = google_compute_network.default_vpc.name
  project       = var.gcp_project_id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = [local.vpc_subnet_cidr]
  target_tags   = ["homelab-gcp-vm"]

  allow {
    protocol = "icmp"
  }
}

# Optional emergency breakglass SSH ingress rule (disabled by default when admin_cidr is null)
resource "google_compute_firewall" "allow_breakglass_ssh" {
  count         = local.enable_admin_ssh_ingress ? 1 : 0
  name          = "homelab-allow-breakglass-ssh"
  network       = google_compute_network.default_vpc.name
  project       = var.gcp_project_id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = [var.admin_cidr]
  target_tags   = ["homelab-gcp-vm"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Explicit deny-all ingress baseline
resource "google_compute_firewall" "deny_all_ingress" {
  name          = "homelab-deny-all-ingress"
  network       = google_compute_network.default_vpc.name
  project       = var.gcp_project_id
  direction     = "INGRESS"
  priority      = 65534
  source_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }
}
