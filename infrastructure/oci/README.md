<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8.0 |
| <a name="requirement_oci"></a> [oci](#requirement\_oci) | ~> 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_oci"></a> [oci](#provider\_oci) | 6.37.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [oci_core_instance.main](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_instance) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_availability_domain"></a> [availability\_domain](#input\_availability\_domain) | Availability domain for compute instances. | `string` | n/a | yes |
| <a name="input_compartment_ocid"></a> [compartment\_ocid](#input\_compartment\_ocid) | OCID of the OCI compartment to deploy resources into. | `string` | n/a | yes |
| <a name="input_fingerprint"></a> [fingerprint](#input\_fingerprint) | Fingerprint of the OCI API key. | `string` | n/a | yes |
| <a name="input_instance_image_ocid"></a> [instance\_image\_ocid](#input\_instance\_image\_ocid) | OCID of the OS image to use for compute instances (Ubuntu 22.04 recommended). | `string` | n/a | yes |
| <a name="input_instance_shape"></a> [instance\_shape](#input\_instance\_shape) | OCI compute shape (e.g., VM.Standard.A1.Flex for Always Free ARM). | `string` | `"VM.Standard.A1.Flex"` | no |
| <a name="input_private_key"></a> [private\_key](#input\_private\_key) | PEM-encoded private key for OCI API authentication. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | OCI region (e.g., us-ashburn-1). | `string` | n/a | yes |
| <a name="input_state_encryption_passphrase"></a> [state\_encryption\_passphrase](#input\_state\_encryption\_passphrase) | Passphrase for OpenTofu state encryption (AES-GCM via PBKDF2). Never hardcode — inject via TF\_VAR\_state\_encryption\_passphrase environment variable. | `string` | n/a | yes |
| <a name="input_tenancy_ocid"></a> [tenancy\_ocid](#input\_tenancy\_ocid) | OCID of the OCI tenancy. | `string` | n/a | yes |
| <a name="input_user_ocid"></a> [user\_ocid](#input\_user\_ocid) | OCID of the OCI user for authentication. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_instance_id"></a> [instance\_id](#output\_instance\_id) | OCID of the provisioned OCI compute instance. |
| <a name="output_private_ip"></a> [private\_ip](#output\_private\_ip) | Private IP address of the OCI compute instance. |
<!-- END_TF_DOCS -->