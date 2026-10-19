# --- Primary Backup Storage (GCS Regional Standard Bucket & Append-Only IAM) ---

# Cloud KMS (CMEK) is a paid service outside the Always Free Tier; Restic encrypts all
# backup data client-side with AES-256 before upload (matching OCI CKV_OCI_9 posture).
#trivy:ignore:AVD-GCP-0066
#trivy:ignore:AVD-GCP-0078
resource "google_storage_bucket" "backups" {
  #checkov:skip=CKV_GCP_62:Dedicated access-log buckets consume the 5 GB Always Free storage quota
  #checkov:skip=CKV_GCP_78:OD-4 (2026-10-19): the uploader identity is append-only (create/read/list); versioning would keep prune churn against the Always Free storage cap.
  name                        = "${var.gcp_project_id}-homelab-backups"
  location                    = var.gcp_region
  project                     = var.gcp_project_id
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  labels = merge(local.default_labels, { role = "backup" }, { project = "homelab" })

  # Restic provides client-side content-addressed snapshot versioning and the VM's custom
  # IAM role is strictly append-only (no delete permission). Enabling GCS object versioning
  # would retain pruned pack files as noncurrent versions and exhaust the 5 GB Always Free limit.
  #trivy:ignore:AVD-GCP-0078
  versioning {
    enabled = false
  }

  soft_delete_policy {
    retention_duration_seconds = 604800
  }

  lifecycle_rule {
    condition {
      age = 7
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

# --- Dedicated Prune Service Account, Custom Role, and HMAC Key for Weekly Backup Prune ---

resource "google_service_account" "backup_pruner" {
  account_id   = "homelab-gcp-backup-pruner"
  display_name = "Homelab Restic Backup Pruner"
  description  = "Dedicated service account for scheduled Restic repository prune and integrity checks"
  project      = var.gcp_project_id
}

resource "google_project_iam_custom_role" "backup_pruner" {
  role_id     = "homelabResticBackupPruner"
  title       = "Homelab Restic Backup Pruner"
  description = "Grants object read/write/delete on GCS backup bucket for out-of-band Restic prune"
  project     = var.gcp_project_id
  permissions = [
    "storage.buckets.get",
    "storage.objects.create",
    "storage.objects.get",
    "storage.objects.list",
    "storage.objects.delete",
    "storage.objects.update",
  ]
}

resource "google_storage_bucket_iam_member" "backup_pruner" {
  bucket = google_storage_bucket.backups.name
  role   = google_project_iam_custom_role.backup_pruner.name
  member = "serviceAccount:${google_service_account.backup_pruner.email}"
}

resource "google_storage_hmac_key" "backup_pruner" {
  service_account_email = google_service_account.backup_pruner.email
  project               = var.gcp_project_id
}
