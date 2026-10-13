mock_provider "google" {}

variables {
  gcp_project_id = "mock-gcp-project-12345"
  gcp_region     = "us-central1"
}

run "reject_non_free_tier_region" {
  command = plan

  variables {
    gcp_region = "europe-west3"
  }

  expect_failures = [
    var.gcp_region,
  ]
}

run "reject_missing_project_label" {
  command = plan

  variables {
    default_labels = {
      environment = "test"
    }
  }

  expect_failures = [
    var.default_labels,
  ]
}

run "reject_invalid_project_label_value" {
  command = plan

  variables {
    default_labels = {
      project = "not-homelab"
    }
  }

  expect_failures = [
    var.default_labels,
  ]
}

run "reject_non_free_instance_type" {
  command = plan

  variables {
    gcp_instance_type = "e2-standard-4"
  }

  expect_failures = [
    var.gcp_instance_type,
  ]
}

run "reject_disk_size_too_large" {
  command = plan

  variables {
    gcp_boot_disk_size_gb = 50
  }

  expect_failures = [
    var.gcp_boot_disk_size_gb,
  ]
}

run "reject_disk_size_too_small" {
  command = plan

  variables {
    gcp_boot_disk_size_gb = 5
  }

  expect_failures = [
    var.gcp_boot_disk_size_gb,
  ]
}

run "reject_non_standard_disk_type" {
  command = plan

  variables {
    gcp_boot_disk_type = "pd-ssd"
  }

  expect_failures = [
    var.gcp_boot_disk_type,
  ]
}

run "reject_malformed_billing_account_id" {
  command = plan

  variables {
    gcp_billing_account_id = "invalid-billing-id"
  }

  expect_failures = [
    var.gcp_billing_account_id,
  ]
}
