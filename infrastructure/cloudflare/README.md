<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8.0 |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement\_cloudflare) | ~> 4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_cloudflare"></a> [cloudflare](#provider\_cloudflare) | 4.52.7 |

## Resources

| Name | Type |
| ---- | ---- |
| [cloudflare_api_token.r2_state_token](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/api_token) | resource |
| [cloudflare_r2_bucket.backups_dr](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/r2_bucket) | resource |
| [cloudflare_r2_bucket.tfstate](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/r2_bucket) | resource |
| [cloudflare_api_token_permission_groups.all](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/data-sources/api_token_permission_groups) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cloudflare_account_id"></a> [cloudflare\_account\_id](#input\_cloudflare\_account\_id) | The Cloudflare account ID for managing R2 and account-level resources. | `string` | n/a | yes |
| <a name="input_cloudflare_api_token"></a> [cloudflare\_api\_token](#input\_cloudflare\_api\_token) | The API token for authenticating with Cloudflare. | `string` | n/a | yes |
| <a name="input_state_encryption_passphrase"></a> [state\_encryption\_passphrase](#input\_state\_encryption\_passphrase) | Passphrase for OpenTofu state and plan encryption. | `string` | `"homelab-state-encryption-passphrase-default"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_r2_access_key_id"></a> [r2\_access\_key\_id](#output\_r2\_access\_key\_id) | The Access Key ID for Cloudflare R2 remote state backend authentication. |
| <a name="output_r2_backup_bucket_name"></a> [r2\_backup\_bucket\_name](#output\_r2\_backup\_bucket\_name) | The name of the secondary R2 disaster recovery backup bucket. |
| <a name="output_r2_backup_endpoint"></a> [r2\_backup\_endpoint](#output\_r2\_backup\_endpoint) | S3-compatible endpoint URL for the EU jurisdictional R2 backup bucket. |
| <a name="output_r2_bucket_name"></a> [r2\_bucket\_name](#output\_r2\_bucket\_name) | The name of the OpenTofu state storage R2 bucket. |
| <a name="output_r2_secret_access_key"></a> [r2\_secret\_access\_key](#output\_r2\_secret\_access\_key) | The Secret Access Key (SHA-256 hash of API token) for Cloudflare R2 remote state backend authentication. |
<!-- END_TF_DOCS -->
