# --- Primary Backup Storage (GCS Regional Standard Bucket & Append-Only IAM) ---

resource "google_storage_bucket" "backups" {
  #checkov:skip=CKV_GCP_62:Dedicated access-log buckets consume the 5 GB Always Free storage quota
  #checkov:skip=CKV_GCP_78:Restic manages client-side snapshot versioning and append-only IAM prevents object deletion during backups
  name                        = "${var.gcp_project_id}-homelab-backups"
  location                    = var.gcp_region
  project                     = var.gcp_project_id
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  labels = merge(local.default_labels, { role = "backup" }, { project = "homelab" })

  versioning {
    enabled = false
  }

  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 1
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }

  lifecycle {
    prevent_destroy = var.enable_prevent_destroy
  }
}

resource "google_service_account" "backup_writer" {
  account_id   = "homelab-gcp-backup-writer"
  display_name = "Homelab Restic Append-Only Backup Writer"
  description  = "Append-only service account for Restic backups to GCS (STD-OT-51)"
  project      = var.gcp_project_id
}

# Custom IAM role with strictly append-only object permissions (no delete/overwrite per STD-OT-51)
resource "google_project_iam_custom_role" "backup_append_only" {
  role_id     = "homelabResticBackupAppendOnly"
  title       = "Homelab Restic Append-Only Backup Writer"
  description = "Grants create/get/list on GCS objects without delete or overwrite permissions (STD-OT-51)"
  project     = var.gcp_project_id
  permissions = [
    "storage.buckets.get",
    "storage.objects.create",
    "storage.objects.get",
    "storage.objects.list",
  ]
}

resource "google_storage_bucket_iam_member" "backup_writer_append_only" {
  bucket = google_storage_bucket.backups.name
  role   = google_project_iam_custom_role.backup_append_only.name
  member = "serviceAccount:${google_service_account.backup_writer.email}"
}

resource "google_storage_hmac_key" "backup_writer" {
  service_account_email = google_service_account.backup_writer.email
  project               = var.gcp_project_id
}
