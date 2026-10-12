output "devices" {
  description = "All enrolled Tailscale devices in the tailnet."
  value       = data.tailscale_devices.all.devices
  sensitive   = true
}

output "auth_key_bootstrap" {
  description = "Bootstrap authentication key for node provisioning."
  value       = tailscale_tailnet_key.bootstrap.key
  sensitive   = true
}
