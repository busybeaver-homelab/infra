resource "google_billing_budget" "monthly_spend_limit" {
  count = var.gcp_billing_account_id != "" ? 1 : 0

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
}
