resource "tailscale_tailnet_settings" "homelab" {
  devices_approval_on                         = true
  devices_auto_updates_on                     = true
  devices_key_duration_days                   = 90
  users_approval_on                           = true
  https_enabled                               = true
  posture_identity_collection_on              = false
  regional_routing_on                         = false
  users_role_allowed_to_join_external_tailnet = "admin"
}
