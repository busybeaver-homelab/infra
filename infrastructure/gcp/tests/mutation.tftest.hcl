mock_provider "google" {}

variables {
  gcp_project_id = "mock-gcp-project-12345"
  gcp_region     = "us-central1"
}

run "initial_apply" {
  command = apply

  assert {
    condition     = google_compute_network.default_vpc.name == "homelab-vpc"
    error_message = "Initial apply must provision homelab-vpc"
  }

  assert {
    condition     = google_compute_network.default_vpc.auto_create_subnetworks == false
    error_message = "VPC must disable auto subnet creation"
  }
}

run "mutate_region" {
  command = plan

  variables {
    gcp_region = "us-east1"
  }

  assert {
    condition     = var.gcp_region == "us-east1"
    error_message = "Mutated region must be accepted within Always Free tier"
  }

  assert {
    condition     = google_compute_network.default_vpc.name == "homelab-vpc"
    error_message = "VPC name must remain unchanged"
  }
}

run "mutate_labels" {
  command = plan

  variables {
    default_labels = {
      project     = "homelab"
      environment = "test-mutation"
    }
  }

  assert {
    condition     = lookup(var.default_labels, "environment", "") == "test-mutation"
    error_message = "Mutated labels must reflect environment attribute"
  }

  assert {
    condition     = lookup(var.default_labels, "project", "") == "homelab"
    error_message = "Mandatory project label must remain homelab"
  }
}
