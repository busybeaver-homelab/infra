mock_provider "oci" {}
mock_provider "sops" {}

variables {
  tenancy_ocid            = "ocid1.tenancy.oc1..test"
  user_ocid               = "ocid1.user.oc1..test"
  fingerprint             = "00:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff"
  private_key             = "mock-private-key-test-string"
  compartment_ocid        = "ocid1.compartment.oc1..test"
  vcn_cidr                = "198.51.100.0/24"
  subnet_cidr             = "198.51.100.0/28"
  admin_cidr              = "203.0.113.0/24"
  tenancy_name            = "testtenancy"
  availability_domain     = "test-ad"
  instance_image_ocid_amd = "ocid1.image.oc1..amd"
  instance_image_ocid_arm = "ocid1.image.oc1..arm"
  tailscale_auth_key      = "tskey-auth-test"
  ssh_public_key          = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey user@test"
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
}
