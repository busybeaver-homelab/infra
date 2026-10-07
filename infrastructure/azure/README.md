# Azure Infrastructure

This directory contains the OpenTofu configurations for managing Microsoft Azure resources.

## Requirements

- OpenTofu >= 1.8.0
- AzureRM Provider
- `TF_VAR_state_encryption_passphrase` must be set for local state encryption.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 3.117.1 |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_consumption_budget_subscription.monthly](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/consumption_budget_subscription) | resource |
| [azurerm_subscription.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/subscription) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_azure_subscription_id"></a> [azure\_subscription\_id](#input\_azure\_subscription\_id) | The Azure subscription ID. | `string` | n/a | yes |
| <a name="input_budget_contact_emails"></a> [budget\_contact\_emails](#input\_budget\_contact\_emails) | List of email addresses to notify when budget thresholds are exceeded. | `list(string)` | `[]` | no |
| <a name="input_state_encryption_passphrase"></a> [state\_encryption\_passphrase](#input\_state\_encryption\_passphrase) | Passphrase for OpenTofu state encryption (AES-GCM via PBKDF2). Never hardcode — inject via TF\_VAR\_state\_encryption\_passphrase environment variable. | `string` | n/a | yes |
<!-- END_TF_DOCS -->
