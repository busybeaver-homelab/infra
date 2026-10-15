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
            "tailscale_auth_key": "tskey-auth-gcp-decoy",
            "budget_alert_recipients": "ci-alerts@example.test,secops@example.test"
          }
        EOT
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

run "verify_mandatory_budget_and_notification_channels" {
  command = plan

  assert {
    condition     = google_billing_budget.monthly_spend_limit.billing_account == "012345-6789AB-CDEF01"
    error_message = "Billing budget must bind to gcp_billing_account_id"
  }

  assert {
    condition     = google_billing_budget.monthly_spend_limit.amount[0].specified_amount[0].units == "1"
    error_message = "Budget ceiling must be 1 USD"
  }

  assert {
    condition     = google_billing_budget.monthly_spend_limit.display_name == "homelab-monthly-spend-budget"
    error_message = "Budget display name must be homelab-monthly-spend-budget"
  }

  assert {
    condition     = length(google_billing_budget.monthly_spend_limit.threshold_rules) == 4
    error_message = "Budget must configure 4 threshold rules (50%, 90%, 100% actual, 100% forecasted)"
  }

  assert {
    condition     = google_billing_budget.monthly_spend_limit.budget_filter[0].credit_types_treatment == "INCLUDE_ALL_CREDITS"
    error_message = "Budget filter must include all credit types"
  }

  assert {
    condition     = length(google_monitoring_notification_channel.budget_email) == 2
    error_message = "Two email notification channels must be created from SOPS gcp.budget_alert_recipients"
  }

  assert {
    condition     = google_monitoring_notification_channel.budget_email["ci-alerts@example.test"].type == "email"
    error_message = "Notification channel type must be email"
  }
}

run "verify_budget_explicit_recipients_override_and_apply" {
  command = apply

  variables {
    budget_alert_recipients = ["override-alert@example.test"]
  }

  assert {
    condition     = length(google_monitoring_notification_channel.budget_email) == 1
    error_message = "Explicit budget_alert_recipients variable must override SOPS recipients"
  }

  assert {
    condition     = length(google_billing_budget.monthly_spend_limit.all_updates_rule[0].monitoring_notification_channels) == 1
    error_message = "Budget all_updates_rule must wire the monitoring notification channel ID"
  }
}
