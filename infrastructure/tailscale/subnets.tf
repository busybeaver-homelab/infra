resource "tailscale_device_subnet_routes" "routes" {
  for_each  = var.device_subnet_routes
  device_id = try(local.device_id_map[each.key], "mock-${each.key}")
  routes    = each.value
}
