<!-- BEGIN_TF_DOCS -->

## Requirements

| Name                                                                     | Version |
| ------------------------------------------------------------------------ | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | 1.16.6  |
| <a name="requirement_google"></a> [google](#requirement_google)          | 8.7.0   |

## Providers

| Name                                                      | Version |
| --------------------------------------------------------- | ------- |
| <a name="provider_google"></a> [google](#provider_google) | 8.7.0   |

## Resources

| Name                                                                                                                                      | Type     |
| ----------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| [google_billing_budget.monthly_spend_limit](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/resources/billing_budget) | resource |
| [google_compute_network.default_vpc](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/resources/compute_network)       | resource |

## Inputs

| Name                                                                                                                 | Description                                                                                                                         | Type          | Default                                         | Required |
| -------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ------------- | ----------------------------------------------- | :------: |
| <a name="input_default_labels"></a> [default\_labels](#input_default_labels)                                         | Default labels applied to all GCP resources. Must include project = 'homelab'.                                                      | `map(string)` | <pre>{<br/> "project": "homelab"<br/>}</pre>    |    no    |
| <a name="input_gcp_billing_account_id"></a> [gcp\_billing\_account\_id](#input_gcp_billing_account_id)               | The GCP billing account ID (e.g., 012345-6789AB-CDEF01) for budget and spend alert management. Leave empty to skip budget creation. | `string`      | `""`                                            |    no    |
| <a name="input_gcp_boot_disk_size_gb"></a> [gcp\_boot\_disk\_size\_gb](#input_gcp_boot_disk_size_gb)                 | The boot disk size in GB. Strictly restricted to the Always Free Tier allowance: 10 to 30 GB.                                       | `number`      | `30`                                            |    no    |
| <a name="input_gcp_boot_disk_type"></a> [gcp\_boot\_disk\_type](#input_gcp_boot_disk_type)                           | The persistent disk type. Strictly restricted to the Always Free Tier type: pd-standard.                                            | `string`      | `"pd-standard"`                                 |    no    |
| <a name="input_gcp_instance_type"></a> [gcp\_instance\_type](#input_gcp_instance_type)                               | The GCP compute instance machine type. Strictly restricted to the Always Free Tier shape: e2-micro.                                 | `string`      | `"e2-micro"`                                    |    no    |
| <a name="input_gcp_project_id"></a> [gcp\_project\_id](#input_gcp_project_id)                                        | The Google Cloud project ID.                                                                                                        | `string`      | n/a                                             |   yes    |
| <a name="input_gcp_region"></a> [gcp\_region](#input_gcp_region)                                                     | The primary Google Cloud region. Must be in the GCP Always Free Tier eligible regions: us-central1, us-east1, us-west1.             | `string`      | `"us-central1"`                                 |    no    |
| <a name="input_state_encryption_passphrase"></a> [state\_encryption\_passphrase](#input_state_encryption_passphrase) | Passphrase for OpenTofu state and plan encryption.                                                                                  | `string`      | `"homelab-state-encryption-passphrase-default"` |    no    |

## Outputs

| Name                                                                                  | Description                             |
| ------------------------------------------------------------------------------------- | --------------------------------------- |
| <a name="output_vpc_network_id"></a> [vpc\_network\_id](#output_vpc_network_id)       | The ID of the scaffolded VPC network.   |
| <a name="output_vpc_network_name"></a> [vpc\_network\_name](#output_vpc_network_name) | The name of the scaffolded VPC network. |

<!-- END_TF_DOCS -->
