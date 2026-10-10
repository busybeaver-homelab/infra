check "enforce_budget_guardrails" {
  assert {
    condition     = azurerm_consumption_budget_subscription.monthly.amount <= 165
    error_message = "Monthly Azure budget amount must not exceed $165 (yearly $2000 ceiling)"
  }

  assert {
    condition     = azurerm_consumption_budget_subscription.monthly.time_grain == "Monthly"
    error_message = "Azure consumption budget time grain must strictly be Monthly"
  }

  assert {
    condition     = alltrue([for n in azurerm_consumption_budget_subscription.monthly.notification : n.enabled == true])
    error_message = "All Azure consumption budget notifications must be enabled"
  }
}
