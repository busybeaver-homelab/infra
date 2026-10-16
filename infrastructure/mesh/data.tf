# Ephemeral SOPS resource for provider credentials (never persisted to state).
ephemeral "sops_file" "secrets" {
  source_file = var.secrets_file_path
}

# Scoped SOPS subtree extraction for non-credential configuration only.
data "external" "sops_config" {
  program = ["bash", "${path.module}/../../scripts/sops-subtree.sh"]
  query = {
    file    = var.secrets_file_path
    extract = "[\"tailscale\"][\"config\"]"
  }
}

# Queries all devices currently enrolled in the tailnet.
data "tailscale_devices" "all" {}

# Queries all users enrolled in the tailnet.
data "tailscale_users" "all" {}

# Parameterized specific device lookup by hostname
data "tailscale_device" "monitored" {
  for_each = nonsensitive(toset(local.monitored_device_hostnames))
  name     = "${each.value}.${local.tailnet_name}"
}
