provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region

  default_labels = local.default_labels
}

provider "sops" {}

provider "tailscale" {
  oauth_client_id     = try(local.sops_ephemeral.tailscale.bootstrap_client_id, "")
  oauth_client_secret = try(local.sops_ephemeral.tailscale.bootstrap_client_secret, "")
  tailnet             = try(local.sops_ephemeral.tailscale.config.tailnet_name, "")
}
