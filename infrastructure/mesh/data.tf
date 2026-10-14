# Decrypts the canonical credentials file at plan time.
data "sops_file" "secrets" {
  source_file = var.secrets_file_path
}

# Queries all devices currently enrolled in the tailnet.
data "tailscale_devices" "all" {}

# Queries all users enrolled in the tailnet.
data "tailscale_users" "all" {}

# Parameterized specific device lookup by hostname
data "tailscale_device" "monitored" {
  for_each = toset(var.monitored_device_hostnames)
  name     = "${each.value}.${local.tailnet_name}"
}
