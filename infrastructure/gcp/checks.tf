check "enforce_network_security_posture" {
  assert {
    condition     = google_compute_network.default_vpc.auto_create_subnetworks == false
    error_message = "VPC must not auto-create subnetworks; custom subnetting required for security"
  }
}

check "enforce_mandatory_project_label" {
  assert {
    condition     = lookup(local.default_labels, "project", "") == "homelab"
    error_message = "Project label 'homelab' is mandatory on all GCP infrastructure"
  }
}

check "enforce_always_free_instance_compliance" {
  assert {
    condition     = var.gcp_instance_type == "e2-micro"
    error_message = "Only e2-micro instance shape is permitted under GCP Always Free Tier"
  }
}

check "enforce_always_free_region_compliance" {
  assert {
    condition     = contains(["us-central1", "us-east1", "us-west1"], var.gcp_region)
    error_message = "GCP region must be an Always Free tier region (us-central1, us-east1, us-west1)"
  }
}

check "enforce_always_free_disk_compliance" {
  assert {
    condition     = var.gcp_boot_disk_type == "pd-standard" && var.gcp_boot_disk_size_gb >= 10 && var.gcp_boot_disk_size_gb <= 30
    error_message = "Boot disk must be pd-standard between 10 and 30 GB under GCP Always Free Tier"
  }
}

check "enforce_billing_account_compliance" {
  assert {
    condition     = var.gcp_billing_account_id == "" || can(regex("^[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$", var.gcp_billing_account_id))
    error_message = "GCP billing account ID format must be valid"
  }
}

check "enforce_budget_guardrails" {
  assert {
    condition     = length(google_billing_budget.monthly_spend_limit) == 0 || (length(google_billing_budget.monthly_spend_limit) == 1 && google_billing_budget.monthly_spend_limit[0].amount[0].specified_amount[0].units == "1")
    error_message = "Billing budget ceiling must be configured to exactly $1.00 USD when active"
  }
}
