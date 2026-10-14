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
  budget_contact_emails       = ["admin@example.com"]
}

run "verify_azure_budget_subscription" {
  command = plan

  assert {
    condition     = azurerm_consumption_budget_subscription.monthly.name == "monthly-subscription-budget"
    error_message = "Azure monthly budget name must be monthly-subscription-budget"
  }

  assert {
    condition     = azurerm_consumption_budget_subscription.monthly.amount == 165
    error_message = "Azure monthly budget amount must be 165"
  }

  assert {
    condition     = azurerm_consumption_budget_subscription.monthly.time_grain == "Monthly"
    error_message = "Azure budget time grain must be Monthly"
  }
}

run "verify_budget_applied_on_apply" {
  command = apply

  assert {
    condition     = azurerm_consumption_budget_subscription.monthly.id != ""
    error_message = "Azure consumption budget ID must be computed on apply"
  }

  assert {
    condition     = azurerm_consumption_budget_subscription.monthly.name == "monthly-subscription-budget"
    error_message = "Azure consumption budget name must match on apply"
  }
}
