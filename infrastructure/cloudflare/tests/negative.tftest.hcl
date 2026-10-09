mock_provider "cloudflare" {}

variables {
  cloudflare_api_token  = "mock-cf-token-12345"
  cloudflare_account_id = "mock-account-id-12345"
}

run "reject_invalid_bucket_name" {
  command = plan

  variables {
    r2_backup_bucket_name = "invalid_bucket_name_with_underscores"
  }

  expect_failures = [
    var.r2_backup_bucket_name,
  ]
}

run "reject_invalid_location_hint" {
  command = plan

  variables {
    r2_backup_location = "INVALID_REGION"
  }

  expect_failures = [
    var.r2_backup_location,
  ]
}
