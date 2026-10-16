resource "tailscale_device_subnet_routes" "routes" {
  for_each  = var.device_subnet_routes
  device_id = lookup(local.device_id_map, each.key, "")
  routes    = each.value

  lifecycle {
    precondition {
      condition     = contains(keys(local.device_id_map), each.key)
      error_message = "Device ${each.key} not found in tailnet discovery or device_id_overrides."
    }
  }
}
