# --- Cloudflare R2 Secondary Disaster Recovery (DR) Backup Bucket ---
# Location hint is set to Western Europe (WEUR) for EU data residency compliance
# and geographic dispersion from the primary backup repository in OCI Frankfurt (eu-frankfurt-1).

resource "cloudflare_r2_bucket" "backups_dr" {
  account_id = var.cloudflare_account_id
  name       = var.r2_backup_bucket_name
  location   = var.r2_backup_location
}
