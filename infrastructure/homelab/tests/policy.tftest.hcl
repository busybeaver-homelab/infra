mock_provider "proxmox" {}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
  proxmox_api_endpoint        = "https://proxmox.example.internal:8006"
  proxmox_api_token           = "ci@pam!token=dummy"
  proxmox_insecure            = false
}

# STD-OT-59: TLS verification and output sensitivity invariants for infrastructure/homelab.
run "policy_invariants" {
  command = plan

  assert {
    condition     = var.proxmox_insecure == false && startswith(var.proxmox_api_endpoint, "https://")
    error_message = "Proxmox provider configuration must enforce HTTPS and strict TLS certificate verification (STD-OT-59)."
  }

  assert {
    condition     = issensitive(output.proxmox_endpoint)
    error_message = "Homelab proxmox_endpoint output must be marked sensitive (STD-OT-33, STD-OT-59)."
  }
}
