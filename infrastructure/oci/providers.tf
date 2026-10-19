provider "oci" {
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
  fingerprint  = var.fingerprint
  private_key  = var.private_key
  region       = var.region
}

provider "sops" {}

provider "tailscale" {
  oauth_client_id     = try(local.sops_ephemeral.tailscale.bootstrap_client_id, "")
  oauth_client_secret = try(local.sops_ephemeral.tailscale.bootstrap_client_secret, "")
  tailnet             = try(local.sops_ephemeral.tailscale.config.tailnet_name, "")
}
