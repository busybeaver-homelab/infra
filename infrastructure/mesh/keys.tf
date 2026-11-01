resource "tailscale_tailnet_key" "roles" {
  for_each      = var.auth_keys
  reusable      = each.value.reusable
  ephemeral     = each.value.ephemeral
  preauthorized = each.value.preauthorized
  expiry        = each.value.expiry
  description   = each.value.description
  tags          = each.value.tags
}

# Single-use, preauthorized enrolment key for the Valetudo robot. A consumed
# or expired key is never recreated automatically; rotate it deliberately
# (tofu apply -replace) when the robot must re-join the tailnet.
resource "tailscale_tailnet_key" "robot" {
  tags                = ["tag:type-iot"]
  reusable            = false
  ephemeral           = false
  preauthorized       = true
  expiry              = var.robot_auth_key_expiry
  description         = "Homelab Valetudo robot single-use enrolment key"
  recreate_if_invalid = "never"
}
