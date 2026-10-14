locals {
  default_labels = merge(var.default_labels, {
    project = "homelab"
  })

  vpc_subnet_cidr = coalesce(
    var.vpc_subnet_cidr != null && trimspace(var.vpc_subnet_cidr) != "" ? var.vpc_subnet_cidr : null,
    try(data.sops_file.secrets.data["gcp.subnet_cidr"], null),
  )

  tailscale_tags     = join(",", concat(var.tailscale_common_tags, var.tailscale_extra_tags_gcp))
  tailscale_auth_key = coalesce(var.tailscale_auth_key != "" ? var.tailscale_auth_key : null, try(data.sops_file.secrets.data["gcp.tailscale_auth_key"], ""))

  sops_budget_recipients = compact([
    for s in split(",", try(data.sops_file.secrets.data["gcp.budget_alert_recipients"], "")) : trimspace(s)
  ])
  budget_alert_recipients = length(var.budget_alert_recipients) > 0 ? var.budget_alert_recipients : local.sops_budget_recipients

  enable_admin_ssh_ingress = var.admin_cidr != null && var.admin_cidr != ""
}
