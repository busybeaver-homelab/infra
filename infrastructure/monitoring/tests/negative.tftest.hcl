mock_provider "healthchecksio" {}

variables {
  healthchecksio_api_key = "mock-healthchecksio-api-key"
}

run "reject_excessive_healthcheck_timeout" {
  command = plan

  variables {
    healthcheck_timeout = 172800 # 48 hours exceeds 24 hour max limit
  }

  expect_failures = [
    var.healthcheck_timeout,
  ]
}

run "reject_inadequate_healthcheck_grace" {
  command = plan

  variables {
    healthcheck_grace = 60 # 1 minute is under the 300s minimum grace period
  }

  expect_failures = [
    var.healthcheck_grace,
  ]
}

run "reject_underflow_healthcheck_timeout" {
  command = plan

  variables {
    healthcheck_timeout = 30 # Under 60 seconds minimum limit
  }

  expect_failures = [
    var.healthcheck_timeout,
  ]
}

run "reject_excessive_healthcheck_grace" {
  command = plan

  variables {
    healthcheck_grace = 20000 # Exceeds 14400s (4h) maximum limit
  }

  expect_failures = [
    var.healthcheck_grace,
  ]
}

