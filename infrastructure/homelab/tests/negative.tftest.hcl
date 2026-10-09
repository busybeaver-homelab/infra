mock_provider "proxmox" {}

variables {
  proxmox_api_endpoint = "https://proxmox.internal:8006/api2/json"
  proxmox_api_token    = "mock-user@pam!mocktoken=mock-secret"
  proxmox_insecure     = false
}

run "reject_insecure_proxmox_tls_bypass" {
  command = plan

  variables {
    proxmox_insecure = true
  }

  expect_failures = [
    var.proxmox_insecure,
  ]
}

run "reject_insecure_http_api_endpoint" {
  command = plan

  variables {
    proxmox_api_endpoint = "http://proxmox.internal:8006/api2/json"
  }

  expect_failures = [
    var.proxmox_api_endpoint,
  ]
}
