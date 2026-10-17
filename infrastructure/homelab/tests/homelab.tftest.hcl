mock_provider "proxmox" {}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
  proxmox_api_endpoint        = "https://proxmox.example.internal:8006"
  proxmox_api_token           = "ci@pam!token=dummy"
  proxmox_insecure            = false
}

run "verify_homelab_configuration" {
  command = plan

  assert {
    condition     = var.proxmox_insecure == false
    error_message = "Proxmox TLS verification must be enforced by default"
  }
}

run "verify_computed_outputs_on_apply" {
  command = apply

  assert {
    condition     = output.proxmox_endpoint == "https://proxmox.example.internal:8006"
    error_message = "Proxmox API endpoint output must match configuration on apply"
  }
}
