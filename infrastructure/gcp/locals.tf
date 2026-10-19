locals {
  sops_ephemeral = try(yamldecode(ephemeral.sops_file.secrets.raw), {})
  gcp_config     = try(jsondecode(data.external.sops_config.result.json), {})

  default_labels = merge(var.default_labels, {
    project = "homelab"
  })

  vpc_subnet_cidr = coalesce(
    var.vpc_subnet_cidr != null && trimspace(var.vpc_subnet_cidr) != "" ? var.vpc_subnet_cidr : null,
    try(local.gcp_config.subnet_cidr, null),
  )

  tailscale_tags = join(",", var.tailscale_bootstrap_tags)

  sops_budget_recipients = compact([
    for s in split(",", try(local.gcp_config.budget_alert_recipients, "")) : trimspace(s)
  ])
  budget_alert_recipients = length(var.budget_alert_recipients) > 0 ? var.budget_alert_recipients : local.sops_budget_recipients

  enable_admin_ssh_ingress = var.admin_cidr != null && var.admin_cidr != ""
}

