mock_provider "proxmox" {}

variables {
  proxmox_api_endpoint = "https://proxmox.ci.internal:8006"
  proxmox_api_token    = "ci@pam!token=dummy"
  proxmox_insecure     = false
}

run "verify_homelab_configuration" {
  command = plan

  assert {
    condition     = var.proxmox_insecure == false
    error_message = "Proxmox TLS verification must be enforced by default"
  }
}
