mock_provider "oci" {}
mock_provider "sops" {}

variables {
  tenancy_ocid            = "ocid1.tenancy.oc1..mock"
  user_ocid               = "ocid1.user.oc1..mock"
  fingerprint             = "00:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff"
  private_key             = "mock-private-key-test-string"
  compartment_ocid        = "ocid1.compartment.oc1..mock"
  vcn_cidr                = "198.51.100.0/24"
  subnet_cidr             = "198.51.100.0/28"
  admin_cidr              = "203.0.113.0/24"
  tenancy_name            = "testtenancy"
  availability_domain     = "ad-1"
  instance_image_ocid_amd = "ocid1.image.oc1..mock-amd"
  instance_image_ocid_arm = "ocid1.image.oc1..mock-arm"
  tailscale_auth_key      = "tskey-auth-test"
  ssh_public_key          = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockKey user@test"
  secrets_file_path       = "../../secrets/credentials.ci.sops.yaml"
  enable_prevent_destroy  = false
}

run "verify_vault_and_key_free_tier" {
  command = plan

  assert {
    condition     = oci_kms_vault.homelab.vault_type == "DEFAULT"
    error_message = "Vault type must default to Standard Virtual Vault (DEFAULT)."
  }

  assert {
    condition     = oci_kms_key.master_key.protection_mode == "SOFTWARE"
    error_message = "Master key must be software-protected."
  }

  assert {
    condition     = oci_kms_key.master_key.key_shape[0].algorithm == "AES"
    error_message = "Key algorithm must be AES-256."
  }
}

run "verify_dynamic_group_and_policy" {
  command = plan

  assert {
    condition     = oci_identity_dynamic_group.homelab_vms.name == "homelab-oci-vms"
    error_message = "Dynamic group name mismatch."
  }

  assert {
    condition     = can(regex("read secret-bundles", oci_identity_policy.vms_read_secrets.statements[0]))
    error_message = "Policy must grant read secret-bundles."
  }
}

run "verify_mandatory_tagging" {
  command = plan

  assert {
    condition     = oci_kms_vault.homelab.freeform_tags["project"] == "homelab"
    error_message = "Vault missing project = homelab tag."
  }

  assert {
    condition     = oci_kms_key.master_key.freeform_tags["project"] == "homelab"
    error_message = "Master key missing project = homelab tag."
  }
}

run "verify_declared_secrets" {
  command = plan

  assert {
    condition     = oci_vault_secret.restic_password.secret_name == "restic_password"
    error_message = "Secret restic_password mismatch."
  }

  assert {
    condition     = oci_vault_secret.restic_secondary_password.secret_name == "restic_secondary_password"
    error_message = "Secret restic_secondary_password mismatch."
  }

  assert {
    condition     = oci_vault_secret.oci_s3_secret_key.secret_name == "oci_s3_secret_key"
    error_message = "Secret oci_s3_secret_key mismatch."
  }

  assert {
    condition     = oci_vault_secret.cloudflare_s3_secret_key.secret_name == "cloudflare_s3_secret_key"
    error_message = "Secret cloudflare_s3_secret_key mismatch."
  }

  assert {
    condition     = oci_vault_secret.healthchecks_ping_url.secret_name == "healthchecks_ping_url"
    error_message = "Secret healthchecks_ping_url mismatch."
  }
}
