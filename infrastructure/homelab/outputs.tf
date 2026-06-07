output "proxmox_endpoint" {
  value       = var.proxmox_api_endpoint
  description = "The configured Proxmox VE API endpoint."
  sensitive   = true
}
