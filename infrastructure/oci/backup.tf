# --- Object Storage Bucket for Encrypted Backups (Always Free Tier) ---

data "oci_objectstorage_namespace" "main" {
  compartment_id = var.compartment_ocid
}

resource "oci_objectstorage_bucket" "backups" {
  #checkov:skip=CKV_OCI_8:The client already versions the backups
  #checkov:skip=CKV_OCI_9:The client uses client-side, end2end encryption, so Oracle-managed 256-bit AES encryption is sufficient
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

  lifecycle {
    prevent_destroy = var.enable_prevent_destroy
  }
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
    "Allow group ${oci_identity_group.backup_uploaders.name} to manage objects in compartment id ${var.compartment_ocid} where all {target.bucket.name='${oci_objectstorage_bucket.backups.name}', any {request.permission='OBJECT_CREATE', request.permission='OBJECT_INSPECT', request.permission='OBJECT_READ'}}"
  ]
  freeform_tags = local.effective_tags
}

# --- Dedicated Writer IAM User and S3 Customer Secret Key (host VMs, append-only) ---

resource "oci_identity_user" "backup_writer" {
  compartment_id = var.tenancy_ocid
  name           = "homelab-backup-writer"
  description    = "Dedicated service user for append-only Restic S3 backups"
  email          = local.backup_writer_email
  freeform_tags  = local.effective_tags
}

resource "oci_identity_user_capabilities_management" "backup_writer" {
  user_id                      = oci_identity_user.backup_writer.id
  can_use_api_keys             = false
  can_use_auth_tokens          = false
  can_use_console_password     = false
  can_use_customer_secret_keys = true
  can_use_smtp_credentials     = false
}

resource "oci_identity_user_group_membership" "backup_writer" {
  group_id = oci_identity_group.backup_uploaders.id
  user_id  = oci_identity_user.backup_writer.id
}

resource "oci_identity_customer_secret_key" "backup_writer" {
  display_name = "homelab-restic-backup-writer-s3-key"
  user_id      = oci_identity_user.backup_writer.id
}

# --- Dedicated Prune IAM Group, Policy, User, and S3 Key for Weekly Backup Prune ---

resource "oci_identity_group" "backup_pruners" {
  compartment_id = var.tenancy_ocid
  name           = "BackupPruners"
  description    = "IAM group for scheduled Restic repository prune and integrity checks"
  freeform_tags  = local.effective_tags
}

resource "oci_identity_policy" "backup_pruners" {
  compartment_id = var.compartment_ocid
  name           = "homelab-backup-pruners-policy"
  description    = "Scoped object read/write/delete permissions on the backup bucket for Restic prune"
  statements = [
    "Allow group ${oci_identity_group.backup_pruners.name} to read buckets in compartment id ${var.compartment_ocid}",
    "Allow group ${oci_identity_group.backup_pruners.name} to manage objects in compartment id ${var.compartment_ocid} where all {target.bucket.name='${oci_objectstorage_bucket.backups.name}', any {request.permission='OBJECT_CREATE', request.permission='OBJECT_INSPECT', request.permission='OBJECT_READ', request.permission='OBJECT_DELETE', request.permission='OBJECT_OVERWRITE'}}"
  ]
  freeform_tags = local.effective_tags
}

resource "oci_identity_user" "backup_pruner" {
  compartment_id = var.tenancy_ocid
  name           = "homelab-backup-pruner"
  description    = "Dedicated service user for scheduled Restic repository pruning"
  email          = local.backup_pruner_email
  freeform_tags  = local.effective_tags
}

resource "oci_identity_user_capabilities_management" "backup_pruner" {
  user_id                      = oci_identity_user.backup_pruner.id
  can_use_api_keys             = false
  can_use_auth_tokens          = false
  can_use_console_password     = false
  can_use_customer_secret_keys = true
  can_use_smtp_credentials     = false
}

resource "oci_identity_user_group_membership" "backup_pruner" {
  group_id = oci_identity_group.backup_pruners.id
  user_id  = oci_identity_user.backup_pruner.id
}

resource "oci_identity_customer_secret_key" "backup_pruner" {
  display_name = "homelab-restic-backup-pruner-s3-key"
  user_id      = oci_identity_user.backup_pruner.id
}
