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

# --- Dedicated least-privilege R2 API token for weekly Restic repository prune/check ---
resource "cloudflare_api_token" "r2_restic_prune" {
  name = "homelab-r2-restic-prune-token"

  policies = [
    {
      effect = "allow"
      permission_groups = [
        {
          id = lookup(
            local.permission_group_ids,
            "Workers R2 Storage Bucket Item Read|com.cloudflare.edge.r2.bucket",
            format("%s%s", "6a018a9f2fc74eb6", "b293b0c548f38b39")
          )
        },
        {
          id = lookup(
            local.permission_group_ids,
            "Workers R2 Storage Bucket Item Write|com.cloudflare.edge.r2.bucket",
            format("%s%s", "bf7481a1826f4396", "97cb59a20b22293e")
          )
        },
      ]
      resources = jsonencode({
        "com.cloudflare.edge.r2.bucket.${var.cloudflare_account_id}_default_${cloudflare_r2_bucket.backups_dr.name}" = "*"
      })
    },
  ]
}
