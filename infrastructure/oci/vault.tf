# --- OCI Key Management & Vault Secrets (Always Free Tier) ---

# 1. Standard Virtual Vault
# ARCHITECTURAL RATIONALE & FREE TIER HARD GATE:
# We explicitly set vault_type = "DEFAULT" (Standard Virtual Vault).
# A "Virtual Private Vault" provides single-tenant dedicated HSM hardware but incurs
# a continuous hourly charge (~$3.00/hour or ~$2,160/year), immediately violating our
# Always Free mandate. Standard Virtual Vaults are multi-tenant and included free.
resource "oci_kms_vault" "homelab" {
  compartment_id = var.compartment_ocid
  display_name   = "homelab-vault"
  vault_type     = "DEFAULT"
  freeform_tags  = local.effective_tags

  lifecycle {
    prevent_destroy = var.enable_prevent_destroy
  }
}

# 2. Software-Protected Master Encryption Key
# ARCHITECTURAL RATIONALE & FREE TIER HARD GATE:
# We explicitly set protection_mode = "SOFTWARE".
# HSM-protected keys are strictly capped at 20 key versions in Always Free tenancies,
# while software-protected AES keys have unlimited free quota across all compartments.
resource "oci_kms_key" "master_key" {
  compartment_id      = var.compartment_ocid
  display_name        = "homelab-master-key"
  management_endpoint = oci_kms_vault.homelab.management_endpoint
  protection_mode     = "SOFTWARE"
  freeform_tags       = local.effective_tags

  key_shape {
    algorithm = "AES"
    length    = 32
  }

  lifecycle {
    prevent_destroy = var.enable_prevent_destroy
  }
}

# 3. Dynamic Group for Compute Instances
# Matches VMs dynamically via compartment and project tag
resource "oci_identity_dynamic_group" "homelab_vms" {
  compartment_id = var.tenancy_ocid
  name           = "homelab-oci-vms"
  description    = "Dynamic group for homelab compute instances accessing Vault secrets"
  matching_rule  = "ALL {instance.compartment.id = '${var.compartment_ocid}', tag.project.value = 'homelab'}"
  freeform_tags  = local.effective_tags
}

# 4. Least-Privilege Read Policy
# Grants read secret-bundles strictly for secrets within the homelab vault
resource "oci_identity_policy" "vms_read_secrets" {
  compartment_id = var.compartment_ocid
  name           = "homelab-vms-read-vault-secrets"
  description    = "Allow homelab VMs to read secret bundles from homelab vault"
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.homelab_vms.name} to read secret-bundles in compartment id ${var.compartment_ocid} where target.vault.id = '${oci_kms_vault.homelab.id}'"
  ]
  freeform_tags = local.effective_tags
}
