mock_provider "google" {}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
  gcp_project_id              = "mock-gcp-project-12345"
  gcp_region                  = "us-central1"
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

run "verify_computed_outputs_on_apply" {
  command = apply

  assert {
    condition     = output.vpc_network_name == "homelab-vpc"
    error_message = "GCP VPC network name output must match homelab-vpc"
  }

  assert {
    condition     = output.vpc_network_id != ""
    error_message = "GCP VPC network ID output must be computed on apply"
  }
}

run "verify_budget_skipped_when_billing_account_empty" {
  command = plan

  assert {
    condition     = length(google_billing_budget.monthly_spend_limit) == 0
    error_message = "Billing budget must not be created when billing account ID is empty"
  }
}

run "verify_budget_resource_when_billing_account_provided" {
  command = plan

  variables {
    gcp_billing_account_id = "012345-6789AB-CDEF01"
  }

  assert {
    condition     = length(google_billing_budget.monthly_spend_limit) == 1
    error_message = "Billing budget must be created when billing account ID is provided"
  }

  assert {
    condition     = google_billing_budget.monthly_spend_limit[0].amount[0].specified_amount[0].units == "1"
    error_message = "Budget ceiling must be exactly 1 USD"
  }

  assert {
    condition     = google_billing_budget.monthly_spend_limit[0].display_name == "homelab-monthly-spend-budget"
    error_message = "Budget display name must be homelab-monthly-spend-budget"
  }

  assert {
    condition     = length(google_billing_budget.monthly_spend_limit[0].threshold_rules) == 4
    error_message = "Budget must configure exactly 4 threshold rules"
  }

  assert {
    condition     = google_billing_budget.monthly_spend_limit[0].budget_filter[0].credit_types_treatment == "INCLUDE_ALL_CREDITS"
    error_message = "Budget filter must include all credit types"
  }
}
