check "enforce_network_security_posture" {
  assert {
    condition     = google_compute_network.default_vpc.auto_create_subnetworks == false && google_compute_subnetwork.private.private_ip_google_access == true
    error_message = "VPC must not auto-create subnetworks and subnet must enable Private Google Access"
  }
}

check "enforce_mandatory_project_label" {
  assert {
    condition     = lookup(local.default_labels, "project", "") == "homelab" && google_compute_instance.default.labels["project"] == "homelab" && google_storage_bucket.backups.labels["project"] == "homelab"
    error_message = "Project label 'homelab' is mandatory on all GCP infrastructure"
  }
}

check "enforce_shielded_vm_posture" {
  assert {
    condition     = google_compute_instance.default.shielded_instance_config[0].enable_secure_boot == true && google_compute_instance.default.shielded_instance_config[0].enable_vtpm == true && google_compute_instance.default.shielded_instance_config[0].enable_integrity_monitoring == true
    error_message = "Shielded VM must enable Secure Boot, vTPM, and Integrity Monitoring"
  }
}

check "enforce_instance_metadata_hardening" {
  assert {
    condition     = google_compute_instance.default.metadata["block-project-ssh-keys"] == "TRUE" && google_compute_instance.default.metadata["serial-port-enable"] == "FALSE" && google_compute_instance.default.metadata["enable-oslogin"] == "TRUE"
    error_message = "Instance metadata must enforce block-project-ssh-keys=TRUE, serial-port-enable=FALSE, and enable-oslogin=TRUE"
  }
}

check "enforce_backup_bucket_security" {
  assert {
    condition     = google_storage_bucket.backups.storage_class == "STANDARD" && google_storage_bucket.backups.uniform_bucket_level_access == true && google_storage_bucket.backups.public_access_prevention == "enforced" && google_storage_bucket.backups.versioning[0].enabled == false
    error_message = "GCS backup bucket must use STANDARD storage class, uniform bucket-level access, enforced public access prevention, and disabled versioning"
  }
}

check "enforce_backup_append_only_iam" {
  assert {
    condition     = !contains(tolist(google_project_iam_custom_role.backup_append_only.permissions), "storage.objects.delete") && !contains(tolist(google_project_iam_custom_role.backup_append_only.permissions), "storage.objects.update")
    error_message = "Backup custom IAM role must be strictly append-only (no delete or update permissions per STD-OT-51)"
  }
}

check "enforce_billing_account_compliance" {
  assert {
    condition     = can(regex("^[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$", var.gcp_billing_account_id))
    error_message = "Mandatory GCP billing account ID format must be valid (STD-OT-41)"
  }
}

check "enforce_budget_guardrails" {
  assert {
    condition     = google_billing_budget.monthly_spend_limit.amount[0].specified_amount[0].units == "1" && length(google_billing_budget.monthly_spend_limit.threshold_rules) == 4
    error_message = "Billing budget ceiling must be configured to $1.00 USD with 4 threshold rules (STD-OT-41)"
  }
}
