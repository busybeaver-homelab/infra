# --- Object Storage Bucket for Encrypted Backups (Always Free Tier) ---

data "oci_objectstorage_namespace" "main" {
  compartment_id = var.compartment_ocid
}

resource "oci_objectstorage_bucket" "backups" {
  compartment_id        = var.compartment_ocid
  name                  = "homelab-backups-${var.tenancy_name}"
  namespace             = data.oci_objectstorage_namespace.main.namespace
  storage_tier          = "Standard"
  access_type           = "NoPublicAccess"
  versioning            = "Disabled"
  object_events_enabled = true

  freeform_tags = merge(local.effective_tags, {
    "Environment" = "Production"
    "Role"        = "Backup"
  })
}

# --- Object Storage Lifecycle Policy (Purge Incomplete Multipart Uploads) ---
# Note: Object lifecycles MUST NOT automatically expire or delete deduplicated Restic blobs.
# Only failed or incomplete multipart uploads are cleaned up after 7 days to preserve free storage.

resource "oci_objectstorage_object_lifecycle_policy" "backups" {
  bucket    = oci_objectstorage_bucket.backups.name
  namespace = data.oci_objectstorage_namespace.main.namespace

  rules {
    action      = "DELETE"
    name        = "abort-incomplete-multipart-uploads"
    time_amount = "7"
    time_unit   = "DAYS"
    target      = "uncommitted-multipart-uploads"
    is_enabled  = true
  }
}

# --- Append-Only IAM Group and Policy for Host Backups ---
# Host VM credentials strictly lack OBJECT_DELETE permissions to mitigate ransomware / host compromise risks.

resource "oci_identity_group" "backup_uploaders" {
  compartment_id = var.tenancy_ocid
  name           = "BackupUploaders"
  description    = "IAM group for append-only host backup operations"
  freeform_tags  = local.effective_tags
}

resource "oci_identity_policy" "backup_uploaders" {
  compartment_id = var.compartment_ocid
  name           = "homelab-backup-uploaders-policy"
  description    = "Append-only permissions for host backup uploaders (strictly no OBJECT_DELETE)"
  statements = [
    "Allow group ${oci_identity_group.backup_uploaders.name} to read buckets in compartment id ${var.compartment_ocid}",
    "Allow group ${oci_identity_group.backup_uploaders.name} to manage objects in compartment id ${var.compartment_ocid} where any {request.permission='OBJECT_CREATE', request.permission='OBJECT_INSPECT', request.permission='OBJECT_READ'}"
  ]
  freeform_tags = local.effective_tags
}
