data "azurerm_subscription" "current" {}

# We enforce a $165 monthly budget limit to ensure we do not exceed $2000 in yearly spending 
# (2000 / 12 = 166.66, rounded down to the nearest multiple of 5 is 165).
resource "azurerm_consumption_budget_subscription" "monthly" {
  name            = "monthly-subscription-budget"
  subscription_id = data.azurerm_subscription.current.id

  amount     = 165
  time_grain = "Monthly"

  time_period {
    start_date = "2026-06-01T00:00:00Z"
  }

  notification {
    enabled        = true
    threshold      = 90.0
    operator       = "EqualTo"
    contact_emails = var.budget_contact_emails
  }

  notification {
    enabled        = true
    threshold      = 100.0
    operator       = "EqualTo"
    contact_emails = var.budget_contact_emails
  }
}
