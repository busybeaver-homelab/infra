# --- OpenTofu remote state bucket (bootstrap: see infrastructure/README.md, Pattern A) ---
resource "cloudflare_r2_bucket" "tfstate" {
  account_id   = var.cloudflare_account_id
  name         = "homelab-infra-tfstate"
  location     = "weur"
  jurisdiction = "default"

  lifecycle {
    prevent_destroy = var.enable_prevent_destroy
  }
}

# --- Secondary disaster recovery (DR) backup bucket ---
# Location hint weur for EU data residency and geographic dispersion from the primary
# backup repository in OCI Frankfurt (eu-frankfurt-1).
resource "cloudflare_r2_bucket" "backups_dr" {
  account_id   = var.cloudflare_account_id
  name         = var.r2_backup_bucket_name
  location     = var.r2_backup_location
  jurisdiction = "default"

  lifecycle {
    prevent_destroy = var.enable_prevent_destroy
  }
}

resource "cloudflare_r2_bucket_lifecycle" "backups_dr" {
  account_id   = var.cloudflare_account_id
  bucket_name  = cloudflare_r2_bucket.backups_dr.name
  jurisdiction = "default"

  rules = [
    {
      id      = "abort-incomplete-multipart-uploads"
      enabled = true
      conditions = {
        prefix = ""
      }
      abort_multipart_uploads_transition = {
        condition = {
          max_age = 604800
          type    = "Age"
        }
      }
    },
  ]
}

