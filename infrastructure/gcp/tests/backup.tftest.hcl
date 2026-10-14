mock_provider "google" {
  override_data {
    target = data.google_compute_image.ubuntu_2604
    values = {
      self_link = "projects/ubuntu-os-cloud/global/images/ubuntu-2604-lts-amd64-v20261014"
    }
  }
}

mock_provider "sops" {
  override_data {
    target = data.sops_file.secrets
    values = {
      data = {
        "gcp.subnet_cidr"             = "198.51.100.0/24"
        "gcp.tailscale_auth_key"      = "tskey-auth-gcp-decoy"
        "gcp.budget_alert_recipients" = "ci-alerts@example.test"
      }
    }
  }
}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
  gcp_project_id              = "mock-gcp-project-12345"
  gcp_region                  = "us-central1"
  gcp_zone                    = "us-central1-a"
  gcp_billing_account_id      = "012345-6789AB-CDEF01"
  enable_prevent_destroy      = false
}

run "verify_gcs_backup_bucket_and_append_only_iam" {
  command = plan

  assert {
    condition     = google_storage_bucket.backups.name == "mock-gcp-project-12345-homelab-backups"
    error_message = "Backup bucket name must be prefixed with project ID"
  }

  assert {
    condition     = google_storage_bucket.backups.location == "US-CENTRAL1" || google_storage_bucket.backups.location == "us-central1"
    error_message = "Backup bucket must be provisioned in the Always Free region"
  }

  assert {
    condition     = google_storage_bucket.backups.storage_class == "STANDARD"
    error_message = "Backup bucket storage_class must be STANDARD (Always Free 5 GB regional allowance)"
  }

  assert {
    condition     = google_storage_bucket.backups.uniform_bucket_level_access == true
    error_message = "Backup bucket must enforce uniform_bucket_level_access"
  }

  assert {
    condition     = google_storage_bucket.backups.public_access_prevention == "enforced"
    error_message = "Backup bucket must enforce public_access_prevention"
  }

  assert {
    condition     = google_storage_bucket.backups.versioning[0].enabled == false
    error_message = "Backup bucket versioning must be disabled to prevent hidden storage costs"
  }

  assert {
    condition     = google_storage_bucket.backups.labels["project"] == "homelab"
    error_message = "Backup bucket must carry mandatory project=homelab label"
  }

  assert {
    condition     = google_service_account.backup_writer.account_id == "homelab-gcp-backup-writer"
    error_message = "Backup writer service account ID must be homelab-gcp-backup-writer"
  }

  assert {
    condition     = contains(tolist(google_project_iam_custom_role.backup_append_only.permissions), "storage.objects.create") && contains(tolist(google_project_iam_custom_role.backup_append_only.permissions), "storage.objects.get") && contains(tolist(google_project_iam_custom_role.backup_append_only.permissions), "storage.objects.list")
    error_message = "Append-only custom IAM role must include create, get, and list permissions"
  }

  assert {
    condition     = !contains(tolist(google_project_iam_custom_role.backup_append_only.permissions), "storage.objects.delete") && !contains(tolist(google_project_iam_custom_role.backup_append_only.permissions), "storage.objects.update")
    error_message = "Append-only custom IAM role must NOT include delete or update permissions (STD-OT-51)"
  }

  assert {
    condition     = google_storage_bucket_iam_member.backup_writer_append_only.bucket == "mock-gcp-project-12345-homelab-backups"
    error_message = "Bucket IAM binding must target the backups bucket"
  }
}

run "verify_backup_outputs_on_apply" {
  command = apply

  assert {
    condition     = output.backup_bucket_name == "mock-gcp-project-12345-homelab-backups"
    error_message = "backup_bucket_name output must match bucket name"
  }

  assert {
    condition     = output.backup_s3_endpoint == "https://storage.googleapis.com"
    error_message = "backup_s3_endpoint output must be https://storage.googleapis.com"
  }

  assert {
    condition     = output.backup_hmac_access_id != "" && output.backup_hmac_secret != ""
    error_message = "HMAC access_id and secret outputs must be populated on apply"
  }
}
