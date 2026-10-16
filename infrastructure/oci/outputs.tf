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

output "backup_s3_access_key_id" {
  value       = oci_identity_customer_secret_key.backup_writer.id
  description = "S3 Customer Secret Key Access Key ID for append-only host Restic backups."
  sensitive   = true
}

output "backup_s3_secret_access_key" {
  value       = oci_identity_customer_secret_key.backup_writer.key
  description = "S3 Customer Secret Key Secret Access Key for append-only host Restic backups."
  sensitive   = true
}

output "backup_prune_s3_access_key_id" {
  value       = oci_identity_customer_secret_key.backup_pruner.id
  description = "S3 Customer Secret Key Access Key ID for scheduled Restic repository pruning."
  sensitive   = true
}

output "backup_prune_s3_secret_access_key" {
  value       = oci_identity_customer_secret_key.backup_pruner.key
  description = "S3 Customer Secret Key Secret Access Key for scheduled Restic repository pruning."
  sensitive   = true
}


output "ansible_inventory" {
  description = "Structured Ansible inventory map for OCI compute instances consumed by scripts/generate-inventory.sh."
  sensitive   = true
  value = merge(
    {
      for idx, inst in oci_core_instance.amd :
      inst.display_name => {
        name         = inst.display_name
        ip           = inst.private_ip
        private_ip   = inst.private_ip
        ansible_host = inst.display_name
        group        = "oci"
        role         = "amd_worker"
      }
    },
    {
      (oci_core_instance.ampere.display_name) = {
        name         = oci_core_instance.ampere.display_name
        ip           = oci_core_instance.ampere.private_ip
        private_ip   = oci_core_instance.ampere.private_ip
        ansible_host = oci_core_instance.ampere.display_name
        group        = "oci"
        role         = "arm_worker"
      }
    }
  )
}
