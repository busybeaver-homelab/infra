mock_provider "azurerm" {
  mock_data "azurerm_subscription" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  azure_subscription_id = "00000000-0000-0000-0000-000000000000"
  budget_contact_emails = ["admin@example.com"]
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
