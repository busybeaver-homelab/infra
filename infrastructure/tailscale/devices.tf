resource "tailscale_device_tags" "nodes" {
  for_each  = var.infrastructure_devices
  device_id = try(local.device_id_map[each.key], "mock-${each.key}")
  tags      = each.value.tags
}

resource "tailscale_device_key" "nodes" {
  for_each            = var.infrastructure_devices
  device_id           = try(local.device_id_map[each.key], "mock-${each.key}")
  key_expiry_disabled = each.value.key_expiry_disabled
}

resource "tailscale_device_authorization" "nodes" {
  for_each   = var.infrastructure_devices
  device_id  = try(local.device_id_map[each.key], "mock-${each.key}")
  authorized = each.value.authorized
}
