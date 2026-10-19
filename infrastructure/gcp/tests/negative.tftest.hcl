mock_provider "google" {
  override_data {
    target = data.google_compute_image.ubuntu_2604
    values = {
      self_link = "projects/ubuntu-os-cloud/global/images/ubuntu-2604-lts-amd64-v20261014"
    }
  }
}

mock_provider "sops" {}

mock_provider "external" {
  override_data {
    target = data.external.sops_config
    values = {
      result = {
        json = <<-EOT
          {
            "subnet_cidr": "198.51.100.0/24",
            "budget_alert_recipients": "ci-alerts@example.test"
          }
        EOT
      }
    }
  }

  override_data {
    target = data.external.sops_tailscale_auth_key
    values = {
      result = {
        json = "\"tskey-auth-gcp-decoy\""
      }
    }
  }
}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
  gcp_project_id              = "mock-gcp-project-12345"
  gcp_region                  = "us-central1"
  gcp_zone                    = "us-central1-a"
  gcp_billing_account_id      = "012345-6789AB-CDEF01"
  enable_prevent_destroy      = false
}

run "reject_non_free_tier_region" {
  command = plan

  variables {
    gcp_region = "europe-west3"
    gcp_zone   = "europe-west3-a"
  }

  expect_failures = [
    var.gcp_region,
  ]
}

run "reject_mismatched_region_and_zone" {
  command = plan

  variables {
    gcp_region = "us-central1"
    gcp_zone   = "us-east1-b"
  }

  expect_failures = [
    var.gcp_zone,
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
    google_compute_instance.default,
  ]
}

run "reject_disk_size_too_large" {
  command = plan

  variables {
    gcp_boot_disk_size_gb = 50
  }

  expect_failures = [
    google_compute_instance.default,
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
    google_compute_instance.default,
  ]
}

run "reject_premium_network_tier" {
  command = plan

  variables {
    gcp_network_tier = "PREMIUM"
  }

  expect_failures = [
    google_compute_instance.default,
  ]
}

run "reject_empty_billing_account_id" {
  command = plan

  variables {
    gcp_billing_account_id = ""
  }

  expect_failures = [
    var.gcp_billing_account_id,
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

run "reject_invalid_vpc_subnet_cidr" {
  command = plan

  variables {
    vpc_subnet_cidr = "invalid-subnet-cidr"
  }

  expect_failures = [
    var.vpc_subnet_cidr,
  ]
}

run "reject_invalid_admin_cidr" {
  command = plan

  variables {
    admin_cidr = "not-a-cidr"
  }

  expect_failures = [
    var.admin_cidr,
  ]
}

run "reject_short_state_encryption_passphrase" {
  command = plan

  variables {
    state_encryption_passphrase = "too-short-test-passphrase"
  }

  expect_failures = [
    var.state_encryption_passphrase,
  ]
}

run "reject_placeholder_state_encryption_passphrase" {
  command = plan

  variables {
    state_encryption_passphrase = "changeme-changeme-changeme-changeme-0001"
  }

  expect_failures = [
    var.state_encryption_passphrase,
  ]
}

run "reject_example_domain_budget_recipient" {
  command = plan

  variables {
    budget_alert_recipients = ["ops@example.com"]
  }

  expect_failures = [
    var.budget_alert_recipients,
  ]
}

run "reject_empty_resolved_budget_alert_recipients" {
  command = plan

  override_data {
    target = data.external.sops_config
    values = {
      result = {
        json = <<-EOT
          {
            "subnet_cidr": "198.51.100.0/24"
          }
        EOT
      }
    }
  }

  expect_failures = [
    google_billing_budget.monthly_spend_limit,
  ]
}
