output "state_bucket_name" {
  value       = google_storage_bucket.state_bucket.name
  description = "The name of the generated GCS remote state bucket."
  sensitive   = true
}

output "state_bucket_url" {
  value       = google_storage_bucket.state_bucket.url
  description = "The URL of the generated GCS remote state bucket."
  sensitive   = true
}
