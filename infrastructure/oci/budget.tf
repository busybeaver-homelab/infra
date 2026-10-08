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
  recipients     = var.budget_alert_recipients
  display_name   = "budget-100-percent-alert"
  message        = "Warning: OCI Free Tier spending has reached 100% of the $1 threshold!"
  freeform_tags  = local.effective_tags
}

# Forecasted spend alert rule (P3-3 / P3-OPS-9)
resource "oci_budget_alert_rule" "forecast_budget_alert" {
  budget_id      = oci_budget_budget.zero_spend.id
  threshold      = var.forecast_budget_alert_threshold
  threshold_type = "PERCENTAGE"
  type           = "FORECAST"
  recipients     = var.budget_alert_recipients
  display_name   = "homelab-forecast-budget-alert"
  message        = "Warning: OCI Free Tier spending is forecasted to reach or exceed 100% of the Always Free budget limit!"
  freeform_tags  = local.effective_tags
}

# ONS Notification Topic for Budget Alerts
resource "oci_ons_notification_topic" "budget_alerts" {
  compartment_id = var.compartment_ocid
  name           = "homelab-budget-alerts"
  description    = "Notification topic for homelab budget alerts and cost forecasting"
  freeform_tags  = local.effective_tags
}

# Optional email subscription to budget notification topic if recipient email is provided
resource "oci_ons_subscription" "budget_alerts_email" {
  count          = var.budget_alert_recipients != "" && !strcontains(var.budget_alert_recipients, "example.com") ? 1 : 0
  compartment_id = var.compartment_ocid
  topic_id       = oci_ons_notification_topic.budget_alerts.id
  endpoint       = var.budget_alert_recipients
  protocol       = "EMAIL"
  freeform_tags  = local.effective_tags
}
