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

run "reject_empty_budget_contact_emails" {
  command = plan

  variables {
    budget_contact_emails = []
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

run "reject_short_state_encryption_passphrase" {
  command = plan

  variables {
    state_encryption_passphrase = "too-short-test-passphrase"
  }

  expect_failures = [
    var.state_encryption_passphrase,
  ]
}

run "reject_placeholder_state_encryption_passphrase" {
  command = plan

  variables {
    state_encryption_passphrase = "changeme-changeme-changeme-changeme-0001"
  }

  expect_failures = [
    var.state_encryption_passphrase,
  ]
}
