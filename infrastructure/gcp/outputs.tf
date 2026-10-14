output "vpc_network_name" {
  value       = google_compute_network.default_vpc.name
  description = "The name of the GCP VPC network."
  sensitive   = true
}

output "vpc_network_id" {
  value       = google_compute_network.default_vpc.id
  description = "The ID of the GCP VPC network."
  sensitive   = true
}

output "subnet_id" {
  value       = google_compute_subnetwork.private.id
  description = "The ID of the private GCP compute subnetwork."
  sensitive   = true
}

output "instance_id" {
  value       = google_compute_instance.default.instance_id
  description = "The unique instance ID of gcp-default-vm."
  sensitive   = true
}

output "instance_name" {
  value       = google_compute_instance.default.name
  description = "The hostname of the GCP compute instance."
  sensitive   = true
}

output "instance_private_ip" {
  value       = google_compute_instance.default.network_interface[0].network_ip
  description = "The internal RFC1918 IPv4 address of gcp-default-vm."
  sensitive   = true
}

output "instance_public_ip" {
  value       = google_compute_instance.default.network_interface[0].access_config[0].nat_ip
  description = "The Standard-Tier ephemeral external IPv4 address of gcp-default-vm."
  sensitive   = true
}

output "vm_service_account_email" {
  value       = google_service_account.vm.email
  description = "Email of the dedicated least-privilege VM service account."
  sensitive   = true
}

output "backup_bucket_name" {
  value       = google_storage_bucket.backups.name
  description = "Name of the GCS regional Standard bucket for primary Restic backups."
  sensitive   = true
}

output "backup_s3_endpoint" {
  value       = "https://storage.googleapis.com"
  description = "S3-compatible endpoint URL for GCS Restic backups."
  sensitive   = true
}

output "backup_hmac_access_id" {
  value       = google_storage_hmac_key.backup_writer.access_id
  description = "HMAC access ID for the append-only backup writer service account."
  sensitive   = true
}

output "backup_hmac_secret" {
  value       = google_storage_hmac_key.backup_writer.secret
  description = "HMAC secret key for the append-only backup writer service account."
  sensitive   = true
}

output "budget_name" {
  value       = google_billing_budget.monthly_spend_limit.name
  description = "Resource name of the mandatory $1 monthly GCP billing budget."
  sensitive   = true
}
