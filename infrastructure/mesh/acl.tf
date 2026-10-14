resource "tailscale_acl" "homelab" {
  acl = templatefile("${path.module}/${var.policy_file_path}", {
    tag_owners = jsonencode(local.tag_owners)
  })
}
