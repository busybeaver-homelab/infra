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
