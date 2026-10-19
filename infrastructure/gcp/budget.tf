# --- Mandatory $1 Billing Budget & Notification Channels (STD-OT-41 / STD-OT-54) ---

resource "google_monitoring_notification_channel" "budget_email" {
  for_each     = toset(nonsensitive(local.budget_alert_recipients))
  project      = var.gcp_project_id
  display_name = "Homelab Budget Alert Email (${each.value})"
  type         = "email"

  labels = {
    email_address = each.value
  }

  user_labels = merge(local.default_labels, { role = "budget-alert" }, { project = "homelab" })
}

resource "google_billing_budget" "monthly_spend_limit" {
  billing_account = var.gcp_billing_account_id
  display_name    = "homelab-monthly-spend-budget"

  budget_filter {
    projects               = ["projects/${var.gcp_project_id}"]
    credit_types_treatment = "INCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = "1"
    }
  }

  threshold_rules {
    threshold_percent = 0.5
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 0.9
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  all_updates_rule {
    monitoring_notification_channels = [
      for ch in google_monitoring_notification_channel.budget_email : ch.id
    ]
    disable_default_iam_recipients = false
  }

  lifecycle {
    precondition {
      condition = (
        length(local.budget_alert_recipients) > 0 &&
        alltrue([for r in local.budget_alert_recipients : !can(regex("(?i)@example\\.(com|org|net)$", r))])
      )
      error_message = "Resolved GCP budget_alert_recipients must contain at least one real email address and no @example.(com|org|net) placeholder (STD-OT-41)."
    }
  }
}
