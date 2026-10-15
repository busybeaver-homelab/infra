output "devices" {
  description = "All enrolled Tailscale devices in the tailnet."
  value       = data.tailscale_devices.all.devices
  sensitive   = true
}

output "auth_key_bootstrap" {
  description = "Bootstrap authentication key for node provisioning."
  value       = tailscale_tailnet_key.bootstrap_oci.key
  sensitive   = true
}

output "auth_key_bootstrap_gcp" {
  description = "Bootstrap authentication key for GCP node provisioning."
  value       = tailscale_tailnet_key.bootstrap_gcp.key
  sensitive   = true
}

output "auth_keys" {
  description = "Map of cloud provider bootstrap authentication keys."
  value = {
    oci = tailscale_tailnet_key.bootstrap_oci.key
    gcp = tailscale_tailnet_key.bootstrap_gcp.key
  }
  sensitive = true
}

output "users" {
  description = "All users enrolled in the Tailscale tailnet."
  value       = data.tailscale_users.all.users
  sensitive   = true
}

output "monitored_devices" {
  description = "Map of monitored Tailscale devices retrieved via data.tailscale_device."
  value       = data.tailscale_device.monitored
  sensitive   = true
}

output "role_auth_keys" {
  description = "Generated role-specific Tailscale authentication keys."
  value       = { for k, v in tailscale_tailnet_key.roles : k => v.key }
  sensitive   = true
}

output "webhook_endpoint_url" {
  description = "Tailnet event webhook endpoint URL."
  value       = length(tailscale_webhook.events) > 0 ? tailscale_webhook.events[0].endpoint_url : ""
  sensitive   = true
}

output "webhook_secret" {
  description = "Tailnet event webhook signing secret."
  value       = length(tailscale_webhook.events) > 0 ? tailscale_webhook.events[0].secret : ""
  sensitive   = true
}
