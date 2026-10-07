<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8.0 |
| <a name="requirement_oci"></a> [oci](#requirement\_oci) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_oci"></a> [oci](#provider\_oci) | 6.37.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [oci_budget_alert_rule.threshold_alert](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/budget_alert_rule) | resource |
| [oci_budget_budget.zero_spend](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/budget_budget) | resource |
| [oci_core_instance.amd](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_instance) | resource |
| [oci_core_instance.ampere](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_instance) | resource |
| [oci_core_nat_gateway.main](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_nat_gateway) | resource |
| [oci_core_route_table.private](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_route_table) | resource |
| [oci_core_security_list.private](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_security_list) | resource |
| [oci_core_subnet.private](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_subnet) | resource |
| [oci_core_vcn.main](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_vcn) | resource |
| [oci_objectstorage_bucket.backups](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/objectstorage_bucket) | resource |
| [oci_objectstorage_namespace.main](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/objectstorage_namespace) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_availability_domain"></a> [availability\_domain](#input\_availability\_domain) | Availability domain for compute instances. | `string` | `""` | no |
| <a name="input_budget_alert_recipients"></a> [budget\_alert\_recipients](#input\_budget\_alert\_recipients) | Email address(es) to receive budget alert notifications (comma-separated). | `string` | `"admin@example.com"` | no |
| <a name="input_budget_alert_threshold"></a> [budget\_alert\_threshold](#input\_budget\_alert\_threshold) | Percentage threshold of the budget amount to trigger alert notification. | `number` | `100` | no |
| <a name="input_budget_amount"></a> [budget\_amount](#input\_budget\_amount) | Monthly spending limit in USD for the OCI budget (set to 1 for zero-spend monitoring). | `number` | `1` | no |
| <a name="input_compartment_ocid"></a> [compartment\_ocid](#input\_compartment\_ocid) | OCID of the OCI compartment to deploy resources into. | `string` | n/a | yes |
| <a name="input_default_freeform_tags"></a> [default\_freeform\_tags](#input\_default\_freeform\_tags) | Default freeform tags applied to all OCI resources. | `map(string)` | <pre>{<br/>  "project": "homelab"<br/>}</pre> | no |
| <a name="input_fingerprint"></a> [fingerprint](#input\_fingerprint) | Fingerprint of the OCI API key. | `string` | n/a | yes |
| <a name="input_instance_image_ocid_amd"></a> [instance\_image\_ocid\_amd](#input\_instance\_image\_ocid\_amd) | OCID of the Ubuntu Minimal OS image for AMD64 instances. | `string` | `""` | no |
| <a name="input_instance_image_ocid_arm"></a> [instance\_image\_ocid\_arm](#input\_instance\_image\_ocid\_arm) | OCID of the Ubuntu Minimal OS image for ARM64 (Ampere) instances. | `string` | `""` | no |
| <a name="input_private_key"></a> [private\_key](#input\_private\_key) | PEM-encoded private key for OCI API authentication. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | OCI region (e.g., eu-frankfurt-1). | `string` | `"eu-frankfurt-1"` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | SSH public key for emergency access to compute instances. | `string` | `""` | no |
| <a name="input_state_encryption_passphrase"></a> [state\_encryption\_passphrase](#input\_state\_encryption\_passphrase) | Passphrase for OpenTofu state encryption (AES-GCM via PBKDF2). Never hardcode — inject via TF\_VAR\_state\_encryption\_passphrase environment variable. | `string` | `""` | no |
| <a name="input_subnet_cidr"></a> [subnet\_cidr](#input\_subnet\_cidr) | IPv4 CIDR block for the private compute subnet. | `string` | n/a | yes |
| <a name="input_tailscale_auth_key"></a> [tailscale\_auth\_key](#input\_tailscale\_auth\_key) | Tailscale authentication key for instance bootstrapping. | `string` | `""` | no |
| <a name="input_tailscale_common_tags"></a> [tailscale\_common\_tags](#input\_tailscale\_common\_tags) | Common Tailscale tags applied across all cloud instances. | `list(string)` | <pre>[<br/>  "tag:type-server",<br/>  "tag:os-linux",<br/>  "tag:hosting-cloud"<br/>]</pre> | no |
| <a name="input_tailscale_extra_tags_oci"></a> [tailscale\_extra\_tags\_oci](#input\_tailscale\_extra\_tags\_oci) | OCI-specific Tailscale tags applied to OCI compute instances. | `list(string)` | <pre>[<br/>  "tag:location-ger",<br/>  "tag:env-oci"<br/>]</pre> | no |
| <a name="input_tenancy_name"></a> [tenancy\_name](#input\_tenancy\_name) | Name of the tenancy used for prefixing globally unique resources like object storage buckets. | `string` | `"homelab"` | no |
| <a name="input_tenancy_ocid"></a> [tenancy\_ocid](#input\_tenancy\_ocid) | OCID of the OCI tenancy. | `string` | n/a | yes |
| <a name="input_user_ocid"></a> [user\_ocid](#input\_user\_ocid) | OCID of the OCI user for authentication. | `string` | n/a | yes |
| <a name="input_vcn_cidr"></a> [vcn\_cidr](#input\_vcn\_cidr) | IPv4 CIDR block for the Virtual Cloud Network (VCN). | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_amd_instance_ids"></a> [amd\_instance\_ids](#output\_amd\_instance\_ids) | OCIDs of the AMD compute instances. |
| <a name="output_amd_private_ips"></a> [amd\_private\_ips](#output\_amd\_private\_ips) | Private IP addresses of the AMD compute instances. |
| <a name="output_arm_instance_id"></a> [arm\_instance\_id](#output\_arm\_instance\_id) | OCID of the Ampere A1 compute instance. |
| <a name="output_arm_private_ip"></a> [arm\_private\_ip](#output\_arm\_private\_ip) | Private IP address of the Ampere A1 compute instance. |
| <a name="output_backup_bucket_name"></a> [backup\_bucket\_name](#output\_backup\_bucket\_name) | Name of the OCI Object Storage bucket for instance backups. |
| <a name="output_backup_s3_endpoint"></a> [backup\_s3\_endpoint](#output\_backup\_s3\_endpoint) | S3 compatibility endpoint URL for Restic backups. |
| <a name="output_budget_id"></a> [budget\_id](#output\_budget\_id) | OCID of the zero-spend monthly budget. |
| <a name="output_nat_gateway_id"></a> [nat\_gateway\_id](#output\_nat\_gateway\_id) | OCID of the NAT gateway. |
| <a name="output_subnet_id"></a> [subnet\_id](#output\_subnet\_id) | OCID of the private compute subnet. |
| <a name="output_vcn_id"></a> [vcn\_id](#output\_vcn\_id) | OCID of the homelab VCN. |
<!-- END_TF_DOCS -->
