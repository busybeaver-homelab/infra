locals {
  sops_oci       = try(jsondecode(data.external.sops_config.result.json), {})
  tailscale_tags = join(",", concat(var.tailscale_common_tags, var.tailscale_extra_tags_oci))
  tailscale_auth_key = coalesce(
    var.tailscale_auth_key != null && trimspace(var.tailscale_auth_key) != "" ? var.tailscale_auth_key : null,
    try(local.sops_oci.tailscale_auth_key, ""),
  )
  admin_cidr = coalesce(
    var.admin_cidr != null && trimspace(var.admin_cidr) != "" ? var.admin_cidr : null,
    try(local.sops_oci.admin_cidr, null),
    var.vcn_cidr,
  )

  # Identity-domain tenancies reject IAM users without an email (HTTP 400). Each user needs a
  # unique address, so the base address is plus-addressed per user; empty omits the attribute.
  backup_service_user_email = var.backup_service_user_email != null && trimspace(var.backup_service_user_email) != "" ? var.backup_service_user_email : try(tostring(local.sops_oci.backup_service_user_email), "")
  backup_writer_email       = local.backup_service_user_email == "" ? null : replace(local.backup_service_user_email, "@", "+restic-writer@")
  backup_pruner_email       = local.backup_service_user_email == "" ? null : replace(local.backup_service_user_email, "@", "+restic-pruner@")

  effective_tags = merge(
    var.default_freeform_tags,
    {
      project = "homelab"
    }
  )
}
