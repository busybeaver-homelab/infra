output "instance_id" {
  value       = oci_core_instance.main.id
  description = "OCID of the provisioned OCI compute instance."
  sensitive   = true
}

output "private_ip" {
  value       = oci_core_instance.main.private_ip
  description = "Private IP address of the OCI compute instance."
  sensitive   = true
}
