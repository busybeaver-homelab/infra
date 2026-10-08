resource "cloudflare_r2_bucket" "tfstate" {
  account_id = var.cloudflare_account_id
  name       = "homelab-infra-tfstate"
  location   = "WEUR"
}

