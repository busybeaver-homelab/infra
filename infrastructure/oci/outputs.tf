output "budget_id" {
  value       = oci_budget_budget.zero_spend.id
  description = "OCID of the zero-spend monthly budget."
  sensitive   = true
}

output "forecast_budget_alert_id" {
  value       = oci_budget_alert_rule.forecast_budget_alert.id
  description = "OCID of the forecasted spend budget alert rule."
  sensitive   = true
}

output "budget_notification_topic_id" {
  value       = oci_ons_notification_topic.budget_alerts.id
  description = "OCID of the budget alerts notification topic."
  sensitive   = true
}

output "vcn_id" {
  value       = oci_core_vcn.main.id
  description = "OCID of the homelab VCN."
  sensitive   = true
}

output "nat_gateway_id" {
  value       = oci_core_nat_gateway.main.id
  description = "OCID of the NAT gateway."
  sensitive   = true
}

output "subnet_id" {
  value       = oci_core_subnet.private.id
  description = "OCID of the private compute subnet."
  sensitive   = true
}

output "amd_instance_ids" {
  value       = oci_core_instance.amd[*].id
  description = "OCIDs of the AMD compute instances."
  sensitive   = true
}

output "amd_private_ips" {
  value       = oci_core_instance.amd[*].private_ip
  description = "Private IP addresses of the AMD compute instances."
  sensitive   = true
}

output "arm_instance_id" {
  value       = oci_core_instance.ampere.id
  description = "OCID of the Ampere A1 compute instance."
  sensitive   = true
}

output "arm_private_ip" {
  value       = oci_core_instance.ampere.private_ip
  description = "Private IP address of the Ampere A1 compute instance."
  sensitive   = true
}

output "backup_bucket_name" {
  value       = oci_objectstorage_bucket.backups.name
  description = "Name of the OCI Object Storage bucket for instance backups."
  sensitive   = true
}

output "backup_s3_endpoint" {
  value       = "https://${data.oci_objectstorage_namespace.main.namespace}.compat.objectstorage.${var.region}.oraclecloud.com"
  description = "S3 compatibility endpoint URL for Restic backups."
  sensitive   = true
}

output "backup_uploaders_group_name" {
  value       = oci_identity_group.backup_uploaders.name
  description = "Name of the append-only IAM group for backup uploads."
  sensitive   = true
}

output "backup_uploaders_policy_id" {
  value       = oci_identity_policy.backup_uploaders.id
  description = "OCID of the append-only IAM policy for backup uploads."
  sensitive   = true
}

output "vault_id" {
  value       = oci_kms_vault.homelab.id
  description = "OCID of the OCI Vault."
  sensitive   = true
}

output "vault_management_endpoint" {
  value       = oci_kms_vault.homelab.management_endpoint
  description = "Management endpoint URL for the OCI Vault."
  sensitive   = true
}

output "master_key_id" {
  value       = oci_kms_key.master_key.id
  description = "OCID of the software-protected master encryption key."
  sensitive   = true
}

output "dynamic_group_name" {
  value       = oci_identity_dynamic_group.homelab_vms.name
  description = "Name of the compute instance dynamic group."
  sensitive   = true
}

output "secret_ids" {
  value = {
    restic_password           = oci_vault_secret.restic_password.id
    restic_secondary_password = oci_vault_secret.restic_secondary_password.id
    oci_s3_secret_key         = oci_vault_secret.oci_s3_secret_key.id
    cloudflare_s3_secret_key  = oci_vault_secret.cloudflare_s3_secret_key.id
    healthchecks_ping_url     = oci_vault_secret.healthchecks_ping_url.id
  }
  description = "Map of secret names to their respective OCI Vault secret OCIDs."
  sensitive   = true
}

