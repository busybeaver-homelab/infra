resource "google_compute_network" "default_vpc" {
  name                    = "homelab-vpc"
  auto_create_subnetworks = false
  project                 = var.gcp_project_id
}
