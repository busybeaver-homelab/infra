# --- OCI Vault Secrets (Seeded from Canonical SOPS) ---

resource "oci_vault_secret" "restic_password" {
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.homelab.id
  key_id         = oci_kms_key.master_key.id
  secret_name    = "restic_password"
  description    = "Primary Restic repository encryption password"
  freeform_tags  = local.effective_tags

  secret_content {
    content_type = "BASE64"
    content      = base64encode(try(data.sops_file.secrets.data["oci_restic.password"], "mock-restic-password"))
  }
}

resource "oci_vault_secret" "restic_secondary_password" {
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.homelab.id
  key_id         = oci_kms_key.master_key.id
  secret_name    = "restic_secondary_password"
  description    = "Secondary Cloudflare R2 Restic repository encryption password"
  freeform_tags  = local.effective_tags

  secret_content {
    content_type = "BASE64"
    content      = base64encode(try(data.sops_file.secrets.data["cloudflare_restic.password"], "mock-secondary-password"))
  }
}

resource "oci_vault_secret" "oci_s3_secret_key" {
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.homelab.id
  key_id         = oci_kms_key.master_key.id
  secret_name    = "oci_s3_secret_key"
  description    = "OCI Object Storage S3 Secret Access Key for backups"
  freeform_tags  = local.effective_tags

  secret_content {
    content_type = "BASE64"
    content      = base64encode(try(data.sops_file.secrets.data["oci_restic.s3_secret_access_key"], "mock-oci-s3-secret-key"))
  }
}

resource "oci_vault_secret" "cloudflare_s3_secret_key" {
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.homelab.id
  key_id         = oci_kms_key.master_key.id
  secret_name    = "cloudflare_s3_secret_key"
  description    = "Cloudflare R2 S3 Secret Access Key for secondary backups"
  freeform_tags  = local.effective_tags

  secret_content {
    content_type = "BASE64"
    content      = base64encode(try(data.sops_file.secrets.data["cloudflare_restic.s3_secret_access_key"], "mock-cf-s3-secret-key"))
  }
}

resource "oci_vault_secret" "healthchecks_ping_url" {
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.homelab.id
  key_id         = oci_kms_key.master_key.id
  secret_name    = "healthchecks_ping_url"
  description    = "Healthchecks.io Ping URL for backup monitoring alerts"
  freeform_tags  = local.effective_tags

  secret_content {
    content_type = "BASE64"
    content      = base64encode(try(data.sops_file.secrets.data["oci.healthchecks_ping_url"], ""))
  }
}
