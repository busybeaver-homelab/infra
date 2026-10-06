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
