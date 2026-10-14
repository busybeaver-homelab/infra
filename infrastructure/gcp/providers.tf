provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region

  default_labels = local.default_labels
}

provider "sops" {}
