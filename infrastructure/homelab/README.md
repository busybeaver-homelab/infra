<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8.0 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | ~> 0.60 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_proxmox_api_endpoint"></a> [proxmox\_api\_endpoint](#input\_proxmox\_api\_endpoint) | The HTTPS API endpoint of the Proxmox VE server. | `string` | n/a | yes |
| <a name="input_proxmox_api_token"></a> [proxmox\_api\_token](#input\_proxmox\_api\_token) | The Proxmox API token (username@realm!tokenid=secret). | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_proxmox_endpoint"></a> [proxmox\_endpoint](#output\_proxmox\_endpoint) | The configured Proxmox VE API endpoint. |
<!-- END_TF_DOCS -->
