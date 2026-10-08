<!-- BEGIN_TF_DOCS -->

## Requirements

| Name                                                                        | Version  |
| --------------------------------------------------------------------------- | -------- |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform)    | >= 1.8.0 |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement_cloudflare) | ~> 4.0   |

## Providers

| Name                                                                  | Version |
| --------------------------------------------------------------------- | ------- |
| <a name="provider_cloudflare"></a> [cloudflare](#provider_cloudflare) | 4.52.7  |

## Resources

| Name                                                                                                                          | Type     |
| ----------------------------------------------------------------------------------------------------------------------------- | -------- |
| [cloudflare_r2_bucket.tfstate](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/r2_bucket) | resource |
| [cloudflare_record.root_record](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/record)   | resource |

## Inputs

| Name                                                                                               | Description                                                            | Type     | Default | Required |
| -------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- | -------- | ------- | :------: |
| <a name="input_cloudflare_account_id"></a> [cloudflare\_account\_id](#input_cloudflare_account_id) | The Cloudflare account ID for managing R2 and account-level resources. | `string` | n/a     |   yes    |
| <a name="input_cloudflare_api_token"></a> [cloudflare\_api\_token](#input_cloudflare_api_token)    | The API token for authenticating with Cloudflare.                      | `string` | n/a     |   yes    |
| <a name="input_cloudflare_zone_id"></a> [cloudflare\_zone\_id](#input_cloudflare_zone_id)          | The target DNS zone ID in Cloudflare.                                  | `string` | n/a     |   yes    |

## Outputs

| Name                                                                                              | Description                                         |
| ------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| <a name="output_r2_bucket_name"></a> [r2\_bucket\_name](#output_r2_bucket_name)                   | The name of the OpenTofu state storage R2 bucket.   |
| <a name="output_root_record_hostname"></a> [root\_record\_hostname](#output_root_record_hostname) | The fully qualified domain name of the root record. |

<!-- END_TF_DOCS -->
