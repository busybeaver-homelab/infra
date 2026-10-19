# --- Budget & Spend Monitoring ---

resource "oci_budget_budget" "zero_spend" {
  compartment_id = var.tenancy_ocid
  amount         = var.budget_amount
  reset_period   = "MONTHLY"
  target_type    = "COMPARTMENT"
  targets        = [var.compartment_ocid]
  display_name   = "zero-spend-monthly-budget"
  description    = "Enforce zero/minimal spend limit for Always Free resources"
  freeform_tags  = local.effective_tags
}

# Actual spend threshold alert
resource "oci_budget_alert_rule" "threshold_alert" {
  budget_id      = oci_budget_budget.zero_spend.id
  threshold      = var.budget_alert_threshold
  threshold_type = "PERCENTAGE"
  type           = "ACTUAL"
  recipients     = local.budget_alert_recipients
  display_name   = "budget-100-percent-alert"
  message        = "Warning: OCI Free Tier spending has reached 100% of the $1 threshold!"
  freeform_tags  = local.effective_tags

  lifecycle {
    precondition {
      condition     = length(trimspace(local.budget_alert_recipients)) > 0 && !can(regex("(?i)@example\\.(com|org|net)(\\b|$)", local.budget_alert_recipients))
      error_message = "Resolved OCI budget_alert_recipients must be non-empty and must not use a placeholder @example.(com|org|net) domain (STD-OT-41)."
    }
  }
}

# Forecasted spend alert rule (P3-3 / P3-OPS-9)
resource "oci_budget_alert_rule" "forecast_budget_alert" {
  budget_id      = oci_budget_budget.zero_spend.id
  threshold      = var.forecast_budget_alert_threshold
  threshold_type = "PERCENTAGE"
  type           = "FORECAST"
  recipients     = local.budget_alert_recipients
  display_name   = "homelab-forecast-budget-alert"
  message        = "Warning: OCI Free Tier spending is forecasted to reach or exceed 100% of the Always Free budget limit!"
  freeform_tags  = local.effective_tags

  lifecycle {
    precondition {
      condition     = length(trimspace(local.budget_alert_recipients)) > 0 && !can(regex("(?i)@example\\.(com|org|net)(\\b|$)", local.budget_alert_recipients))
      error_message = "Resolved OCI budget_alert_recipients must be non-empty and must not use a placeholder @example.(com|org|net) domain (STD-OT-41)."
    }
  }
}
