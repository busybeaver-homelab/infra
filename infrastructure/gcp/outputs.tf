output "vpc_network_name" {
  value       = google_compute_network.default_vpc.name
  description = "The name of the scaffolded VPC network."
  sensitive   = true
}

output "vpc_network_id" {
  value       = google_compute_network.default_vpc.id
  description = "The ID of the scaffolded VPC network."
  sensitive   = true
}
