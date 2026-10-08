mock_provider "google" {}

variables {
  gcp_project_id = "mock-gcp-project-12345"
  gcp_region     = "us-central1"
}

run "verify_gcp_vpc_network" {
  command = plan

  assert {
    condition     = google_compute_network.default_vpc.name == "homelab-vpc"
    error_message = "GCP VPC network must be named homelab-vpc"
  }

  assert {
    condition     = google_compute_network.default_vpc.auto_create_subnetworks == false
    error_message = "GCP VPC network must have auto_create_subnetworks disabled"
  }

  assert {
    condition     = google_compute_network.default_vpc.project == "mock-gcp-project-12345"
    error_message = "GCP VPC network must use the configured project ID"
  }
}
