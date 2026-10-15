locals {
  sops_oci           = try(jsondecode(data.external.sops_config.result.json), {})
  tailscale_tags     = join(",", concat(var.tailscale_common_tags, var.tailscale_extra_tags_oci))
  tailscale_auth_key = coalesce(var.tailscale_auth_key != "" ? var.tailscale_auth_key : null, try(local.sops_oci.tailscale_auth_key, ""))
  admin_cidr         = coalesce(var.admin_cidr != "" ? var.admin_cidr : null, try(local.sops_oci.admin_cidr, null), var.vcn_cidr)

  effective_tags = merge(
    var.default_freeform_tags,
    {
      project = "homelab"
    }
  )
}
