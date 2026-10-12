# Decrypts the canonical credentials file at plan time.
data "sops_file" "secrets" {
  source_file = var.secrets_file_path
}

# Queries all devices currently enrolled in the tailnet.
data "tailscale_devices" "all" {}
