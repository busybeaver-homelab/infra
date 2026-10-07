terraform {
  backend "s3" {
    endpoint                    = "https://<account_id>.eu.r2.cloudflarestorage.com"
    bucket                      = "homelab-infra-tfstate"
    key                         = "homelab-infra/state/homelab/tofu.tfstate"
    region                      = "auto"
    use_lockfile                = true
    force_path_style            = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}
