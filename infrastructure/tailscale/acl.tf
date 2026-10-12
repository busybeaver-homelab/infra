resource "tailscale_acl" "homelab" {
  acl = file("${path.module}/${var.policy_file_path}")
}
