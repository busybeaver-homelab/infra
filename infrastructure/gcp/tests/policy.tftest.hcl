mock_provider "google" {
  override_data {
    target = data.google_compute_image.ubuntu_2604
    values = {
      self_link = "projects/ubuntu-os-cloud/global/images/ubuntu-2604-lts-amd64-v20261014"
    }
  }
}

mock_provider "sops" {}

mock_provider "external" {
  override_data {
    target = data.external.sops_config
    values = {
      result = {
        json = <<-EOT
          {
            "subnet_cidr": "198.51.100.0/24",
            "tailscale_auth_key": "tskey-auth-gcp-decoy",
            "budget_alert_recipients": "ci-alerts@example.test"
          }
        EOT
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

# STD-OT-59: Security and Always Free policy invariants for infrastructure/gcp.
run "policy_invariants" {
  command = plan

  assert {
    condition = (
      google_compute_instance.default.machine_type == "e2-micro" &&
      contains(["us-west1", "us-central1", "us-east1"], var.gcp_region) &&
      startswith(google_compute_instance.default.zone, "${var.gcp_region}-") &&
      google_compute_instance.default.boot_disk[0].initialize_params[0].type == "pd-standard" &&
      google_compute_instance.default.boot_disk[0].initialize_params[0].size <= 30 &&
      google_compute_instance.default.network_interface[0].access_config[0].network_tier == "STANDARD" &&
      tonumber(google_billing_budget.monthly_spend_limit.amount[0].specified_amount[0].units) <= 1
    )
    error_message = "GCP compute, disk, network tier, and billing budget must remain within Always Free ceilings (STD-OT-39, STD-OT-49, STD-OT-59)."
  }

  assert {
    condition = (
      google_compute_instance.default.shielded_instance_config[0].enable_secure_boot == true &&
      google_compute_instance.default.shielded_instance_config[0].enable_vtpm == true &&
      google_compute_instance.default.shielded_instance_config[0].enable_integrity_monitoring == true &&
      google_compute_instance.default.metadata["block-project-ssh-keys"] == "TRUE" &&
      google_compute_instance.default.metadata["serial-port-enable"] == "FALSE" &&
      google_compute_instance.default.metadata["enable-oslogin"] == "TRUE"
    )
    error_message = "GCP instance must enforce Shielded VM (Secure Boot, vTPM, Integrity Monitoring), OS Login, blocked project SSH keys, and disabled serial port (STD-OT-49, STD-OT-59)."
  }

  assert {
    condition = (
      strcontains(google_compute_instance.default.metadata["user-data"], "--auth-key=file:/run/ts.key") &&
      strcontains(google_compute_instance.default.metadata["user-data"], "shred -u /run/ts.key") &&
      !strcontains(google_compute_instance.default.metadata["user-data"], "--authkey=")
    )
    error_message = "GCP instance user-data must deliver Tailscale auth key via /run/ts.key and shred it after use (STD-OT-49, STD-OT-59)."
  }

  assert {
    condition = (
      google_compute_network.default_vpc.auto_create_subnetworks == false &&
      google_compute_subnetwork.private.private_ip_google_access == true &&
      length(google_compute_firewall.allow_breakglass_ssh) == 0
    )
    error_message = "GCP VPC must disable auto_create_subnetworks, enable Private Google Access, and keep breakglass SSH disabled by default (STD-OT-49, STD-OT-59)."
  }

  assert {
    condition = (
      google_storage_bucket.backups.public_access_prevention == "enforced" &&
      google_storage_bucket.backups.uniform_bucket_level_access == true &&
      google_storage_bucket.backups.storage_class == "STANDARD" &&
      google_storage_bucket.backups.versioning[0].enabled == false &&
      !contains(tolist(google_project_iam_custom_role.backup_append_only.permissions), "storage.objects.delete") &&
      !contains(tolist(google_project_iam_custom_role.backup_append_only.permissions), "storage.objects.update")
    )
    error_message = "GCS backup bucket must enforce public_access_prevention, uniform bucket-level access, disabled versioning, and append-only IAM without delete/update (STD-OT-51, STD-OT-59)."
  }

  assert {
    condition = (
      google_compute_instance.default.labels["project"] == "homelab" &&
      google_storage_bucket.backups.labels["project"] == "homelab"
    )
    error_message = "All labelable GCP resources must carry labels[\"project\"] == \"homelab\" (STD-OT-37, STD-OT-59)."
  }
}
