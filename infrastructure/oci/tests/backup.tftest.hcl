mock_provider "oci" {}
mock_provider "sops" {}

mock_provider "external" {
  override_data {
    target = data.external.sops_config
    values = {
      result = {
        json = "{\"budget_alert_recipients\":\"alerts@example.test\"}"
      }
    }
  }

  override_data {
    target = data.external.sops_tailscale_auth_key
    values = {
      result = {
        json = "\"tskey-auth-oci-decoy\""
      }
    }
  }
}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
  tenancy_ocid                = "ocid1.tenancy.oc1..test"
  user_ocid                   = "ocid1.user.oc1..test"
  fingerprint                 = "00:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff"
  private_key                 = "mock-private-key-test-string"
  compartment_ocid            = "ocid1.compartment.oc1..test"
  vcn_cidr                    = "198.51.100.0/24"
  subnet_cidr                 = "198.51.100.0/28"
  admin_cidr                  = "203.0.113.0/24"
  tenancy_name                = "testtenancy"
  availability_domain         = "test-ad"
  instance_image_ocid_amd     = "ocid1.image.oc1..amd"
  instance_image_ocid_arm     = "ocid1.image.oc1..arm"
  tailscale_auth_key          = "tskey-auth-test"
  ssh_public_key              = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey user@test"
}

run "verify_backup_bucket_and_lifecycle" {
  command = plan

  assert {
    condition     = oci_objectstorage_bucket.backups.name == "homelab-backups-testtenancy"
    error_message = "Backup bucket name must follow pattern homelab-backups-<tenancy_name>"
  }

  assert {
    condition     = oci_objectstorage_bucket.backups.freeform_tags["project"] == "homelab"
    error_message = "Backup bucket must have mandatory project=homelab tag"
  }

  assert {
    condition     = oci_objectstorage_bucket.backups.object_events_enabled == true
    error_message = "Backup bucket must have object events enabled"
  }

  assert {
    condition     = length(oci_objectstorage_object_lifecycle_policy.backups.rules) > 0
    error_message = "Backup bucket must have at least one lifecycle rule"
  }

  assert {
    condition     = contains([for r in oci_objectstorage_object_lifecycle_policy.backups.rules : r.target], "uncommitted-multipart-uploads")
    error_message = "Backup lifecycle rule must target uncommitted multipart uploads"
  }

  assert {
    condition     = contains([for r in oci_objectstorage_object_lifecycle_policy.backups.rules : tostring(r.time_amount)], "7")
    error_message = "Backup lifecycle rule must purge incomplete multipart uploads after 7 days"
  }

  assert {
    condition     = oci_identity_group.backup_uploaders.name == "BackupUploaders"
    error_message = "Backup uploaders IAM group must be named BackupUploaders"
  }

  assert {
    condition     = length(oci_identity_policy.backup_uploaders.statements) == 2
    error_message = "Backup uploaders policy must contain exactly two append-only statements"
  }

  assert {
    condition     = oci_identity_user.backup_writer.name == "homelab-backup-writer" && oci_identity_user.backup_writer.freeform_tags["project"] == "homelab"
    error_message = "OCI backup writer IAM user must be named homelab-backup-writer and carry project=homelab tag"
  }

  assert {
    condition     = oci_identity_customer_secret_key.backup_writer.display_name == "homelab-restic-backup-writer-s3-key"
    error_message = "OCI backup writer customer secret key must be configured for S3-compatible Restic uploads"
  }

  assert {
    condition     = oci_identity_group.backup_pruners.name == "BackupPruners" && oci_identity_group.backup_pruners.freeform_tags["project"] == "homelab"
    error_message = "OCI backup pruners IAM group must be named BackupPruners and carry project=homelab tag"
  }

  assert {
    condition     = length(oci_identity_policy.backup_pruners.statements) == 2 && strcontains(oci_identity_policy.backup_pruners.statements[1], "target.bucket.name='homelab-backups-testtenancy'") && strcontains(oci_identity_policy.backup_pruners.statements[1], "OBJECT_DELETE")
    error_message = "OCI backup pruners policy must scope OBJECT_DELETE permissions to the backups bucket"
  }

  assert {
    condition     = oci_identity_user.backup_pruner.name == "homelab-backup-pruner" && oci_identity_user.backup_pruner.freeform_tags["project"] == "homelab"
    error_message = "OCI backup pruner IAM user must be named homelab-backup-pruner and carry project=homelab tag"
  }

  assert {
    condition     = oci_identity_customer_secret_key.backup_pruner.display_name == "homelab-restic-backup-pruner-s3-key"
    error_message = "OCI backup pruner customer secret key must be configured for S3-compatible Restic pruning"
  }

  assert {
    condition     = strcontains(oci_identity_policy.backup_uploaders.statements[1], "target.bucket.name='homelab-backups-testtenancy'") && !strcontains(oci_identity_policy.backup_uploaders.statements[1], "OBJECT_DELETE") && !strcontains(oci_identity_policy.backup_uploaders.statements[1], "OBJECT_OVERWRITE")
    error_message = "OCI backup uploaders policy must be scoped to the backups bucket and stay append-only (no OBJECT_DELETE / OBJECT_OVERWRITE)"
  }

  assert {
    condition     = oci_identity_user_capabilities_management.backup_writer.can_use_customer_secret_keys == true && oci_identity_user_capabilities_management.backup_writer.can_use_console_password == false && oci_identity_user_capabilities_management.backup_pruner.can_use_customer_secret_keys == true && oci_identity_user_capabilities_management.backup_pruner.can_use_console_password == false
    error_message = "OCI backup writer and pruner users must only enable customer secret keys and disable console passwords"
  }
}

run "verify_backup_user_email_plus_addressing" {
  command = plan

  variables {
    backup_service_user_email = "ops@example.test"
  }

  assert {
    condition     = oci_identity_user.backup_writer.email == "ops+restic-writer@example.test" && oci_identity_user.backup_pruner.email == "ops+restic-pruner@example.test"
    error_message = "OCI backup IAM users must get unique plus-addressed emails derived from backup_service_user_email"
  }
}

run "reject_plus_addressed_backup_user_email" {
  command = plan

  variables {
    backup_service_user_email = "ops+x@example.test"
  }

  expect_failures = [var.backup_service_user_email]
}

run "verify_backup_s3_outputs_on_apply" {
  command = apply

  variables {
    enable_prevent_destroy = false
  }

  assert {
    condition     = output.backup_bucket_name == "homelab-backups-testtenancy"
    error_message = "backup_bucket_name output must match bucket name"
  }

  assert {
    condition     = output.backup_s3_access_key_id != "" && output.backup_s3_secret_access_key != ""
    error_message = "OCI backup writer S3 access_key_id and secret_access_key outputs must be populated on apply"
  }

  assert {
    condition     = output.backup_prune_s3_access_key_id != "" && output.backup_prune_s3_secret_access_key != ""
    error_message = "OCI backup pruner S3 access_key_id and secret_access_key outputs must be populated on apply"
  }
}
