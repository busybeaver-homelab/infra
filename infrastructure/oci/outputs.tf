output "budget_id" {
  value       = oci_budget_budget.zero_spend.id
  description = "OCID of the zero-spend monthly budget."
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
