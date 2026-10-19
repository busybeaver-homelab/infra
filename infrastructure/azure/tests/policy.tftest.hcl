mock_provider "azurerm" {
  mock_data "azurerm_subscription" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
  azure_subscription_id       = "00000000-0000-0000-0000-000000000000"
  budget_contact_emails       = ["alerts@example.test"]
}

# STD-OT-59: Cost ceiling and budget notification policy invariants for infrastructure/azure.
run "policy_invariants" {
  command = plan

  assert {
    condition     = azurerm_consumption_budget_subscription.monthly.amount <= 165 && azurerm_consumption_budget_subscription.monthly.time_grain == "Monthly"
    error_message = "Azure monthly subscription budget must not exceed the approved $165/month ceiling (STD-OT-39, STD-OT-59)."
  }

  assert {
    condition = (
      alltrue([for n in azurerm_consumption_budget_subscription.monthly.notification : n.enabled == true && length(n.contact_emails) > 0]) &&
      contains([for n in azurerm_consumption_budget_subscription.monthly.notification : n.threshold], 90) &&
      contains([for n in azurerm_consumption_budget_subscription.monthly.notification : n.threshold], 100)
    )
    error_message = "Azure monthly budget must enforce enabled notifications at 90% and 100% thresholds with non-empty contact_emails (STD-OT-39, STD-OT-59)."
  }
}
