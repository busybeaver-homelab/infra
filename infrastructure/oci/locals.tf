locals {
  oci_config              = try(jsondecode(data.external.sops_config.result.json), {})
  sops_tailscale_auth_key = try(tostring(jsondecode(data.external.sops_tailscale_auth_key.result.json)), "")
  tailscale_tags          = join(",", concat(var.tailscale_common_tags, var.tailscale_extra_tags_oci))
  tailscale_auth_key = coalesce(
    var.tailscale_auth_key != null && trimspace(var.tailscale_auth_key) != "" ? var.tailscale_auth_key : null,
    local.sops_tailscale_auth_key,
  )
  admin_cidr = coalesce(
    var.admin_cidr != null && trimspace(var.admin_cidr) != "" ? var.admin_cidr : null,
    try(local.oci_config.admin_cidr, null),
    var.vcn_cidr,
  )
  budget_alert_recipients = var.budget_alert_recipients != null && trimspace(var.budget_alert_recipients) != "" ? var.budget_alert_recipients : try(tostring(local.oci_config.budget_alert_recipients), "")

  # Identity-domain tenancies reject IAM users without an email (HTTP 400). Each user needs a
  # unique address, so the base address is plus-addressed per user; empty omits the attribute.
  backup_service_user_email = var.backup_service_user_email != null && trimspace(var.backup_service_user_email) != "" ? var.backup_service_user_email : try(tostring(local.oci_config.backup_service_user_email), "")

  backup_writer_email = local.backup_service_user_email == "" ? null : replace(local.backup_service_user_email, "@", "+restic-writer@")
  backup_pruner_email = local.backup_service_user_email == "" ? null : replace(local.backup_service_user_email, "@", "+restic-pruner@")

  effective_tags = merge(
    var.default_freeform_tags,
    {
      project = "homelab"
    }
  )
}
