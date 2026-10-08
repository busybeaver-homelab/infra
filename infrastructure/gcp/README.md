<!-- BEGIN_TF_DOCS -->

## Requirements

| Name                                                                     | Version  |
| ------------------------------------------------------------------------ | -------- |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | >= 1.8.0 |
| <a name="requirement_google"></a> [google](#requirement_google)          | ~> 6.0   |

## Providers

| Name                                                      | Version |
| --------------------------------------------------------- | ------- |
| <a name="provider_google"></a> [google](#provider_google) | 6.50.0  |

## Resources

| Name                                                                                                                                 | Type     |
| ------------------------------------------------------------------------------------------------------------------------------------ | -------- |
| [google_compute_network.default_vpc](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network) | resource |

## Inputs

| Name                                                                          | Description                                                                                                             | Type     | Default         | Required |
| ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | -------- | --------------- | :------: |
| <a name="input_gcp_project_id"></a> [gcp\_project\_id](#input_gcp_project_id) | The Google Cloud project ID.                                                                                            | `string` | n/a             |   yes    |
| <a name="input_gcp_region"></a> [gcp\_region](#input_gcp_region)              | The primary Google Cloud region. Must be in the GCP Always Free Tier eligible regions: us-central1, us-east1, us-west1. | `string` | `"us-central1"` |    no    |

## Outputs

| Name                                                                                  | Description                             |
| ------------------------------------------------------------------------------------- | --------------------------------------- |
| <a name="output_vpc_network_id"></a> [vpc\_network\_id](#output_vpc_network_id)       | The ID of the scaffolded VPC network.   |
| <a name="output_vpc_network_name"></a> [vpc\_network\_name](#output_vpc_network_name) | The name of the scaffolded VPC network. |

<!-- END_TF_DOCS -->
