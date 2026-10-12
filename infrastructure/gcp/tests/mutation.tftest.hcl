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

  assert {
    condition     = lookup(local.default_labels, "project", "") == "homelab"
    error_message = "Mandatory project label must be homelab in local.default_labels"
  }
}

run "mutate_region_to_us_west1" {
  command = plan

  variables {
    gcp_region = "us-west1"
  }

  assert {
    condition     = var.gcp_region == "us-west1"
    error_message = "Region mutation to us-west1 must be accepted within Always Free tier"
  }
}

run "mutate_with_budget_and_labels" {
  command = apply

  variables {
    gcp_billing_account_id = "012345-6789AB-CDEF01"
    default_labels = {
      project     = "homelab"
      environment = "mutation-stage"
      managed_by  = "opentofu"
    }
  }

  assert {
    condition     = length(google_billing_budget.monthly_spend_limit) == 1
    error_message = "Billing budget must be created on apply when billing account ID is provided"
  }

  assert {
    condition     = google_billing_budget.monthly_spend_limit[0].billing_account == "012345-6789AB-CDEF01"
    error_message = "Billing account on budget resource must match variable input"
  }

  assert {
    condition     = lookup(local.default_labels, "project", "") == "homelab"
    error_message = "Mandatory project label must be homelab in local.default_labels"
  }

  assert {
    condition     = lookup(local.default_labels, "managed_by", "") == "opentofu"
    error_message = "Additional label must be preserved in local.default_labels"
  }
}

