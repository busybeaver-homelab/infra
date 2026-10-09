# --- OpenTofu remote state bucket (bootstrap: see infrastructure/README.md, Pattern A) ---
resource "cloudflare_r2_bucket" "tfstate" {
  account_id   = var.cloudflare_account_id
  name         = "homelab-infra-tfstate"
  location     = "WEUR"
  jurisdiction = "default"

  lifecycle {
    prevent_destroy = true
  }
}

# --- Secondary disaster recovery (DR) backup bucket ---
# Location hint WEUR for EU data residency and geographic dispersion from the primary
# backup repository in OCI Frankfurt (eu-frankfurt-1).
resource "cloudflare_r2_bucket" "backups_dr" {
  account_id   = var.cloudflare_account_id
  name         = var.r2_backup_bucket_name
  location     = var.r2_backup_location
  jurisdiction = "default"

  lifecycle {
    prevent_destroy = true
  }
}
