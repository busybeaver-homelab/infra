mock_provider "azurerm" {
  mock_data "azurerm_subscription" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  azure_subscription_id = "00000000-0000-0000-0000-000000000000"
}

run "reject_excessive_monthly_budget" {
  command = plan

  variables {
    monthly_budget_amount = 200
  }

  expect_failures = [
    var.monthly_budget_amount,
  ]
}

run "reject_invalid_budget_email" {
  command = plan

  variables {
    budget_contact_emails = ["not-an-email-address"]
  }

  expect_failures = [
    var.budget_contact_emails,
  ]
}

run "reject_zero_monthly_budget" {
  command = plan

  variables {
    monthly_budget_amount = 0
  }

  expect_failures = [
    var.monthly_budget_amount,
  ]
}

