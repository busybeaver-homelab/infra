check "enforce_proxmox_tls_security" {
  assert {
    condition     = var.proxmox_insecure == false
    error_message = "Proxmox API TLS verification must not be bypassed"
  }

  assert {
    condition     = startswith(var.proxmox_api_endpoint, "https://")
    error_message = "Proxmox API endpoint must use secure HTTPS protocol"
  }
}
