resource "tailscale_device_tags" "nodes" {
  for_each  = nonsensitive(local.infrastructure_devices)
  device_id = lookup(local.device_id_map, each.key, "")
  tags      = each.value.tags

  lifecycle {
    precondition {
      condition     = contains(keys(local.device_id_map), each.key)
      error_message = "Device ${each.key} not found in tailnet discovery or device_id_overrides."
    }
  }
}

resource "tailscale_device_key" "nodes" {
  for_each            = nonsensitive(local.infrastructure_devices)
  device_id           = lookup(local.device_id_map, each.key, "")
  key_expiry_disabled = each.value.key_expiry_disabled

  lifecycle {
    precondition {
      condition     = contains(keys(local.device_id_map), each.key)
      error_message = "Device ${each.key} not found in tailnet discovery or device_id_overrides."
    }
  }
}

resource "tailscale_device_authorization" "nodes" {
  for_each   = nonsensitive(local.infrastructure_devices)
  device_id  = lookup(local.device_id_map, each.key, "")
  authorized = each.value.authorized

  lifecycle {
    precondition {
      condition     = contains(keys(local.device_id_map), each.key)
      error_message = "Device ${each.key} not found in tailnet discovery or device_id_overrides."
    }
  }
}
