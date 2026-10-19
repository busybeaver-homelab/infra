locals {
  sops_ephemeral = try(yamldecode(ephemeral.sops_file.secrets.raw), {})
  oci_config     = try(jsondecode(data.external.sops_config.result.json), {})
  tailscale_tags = join(",", var.tailscale_bootstrap_tags)
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
