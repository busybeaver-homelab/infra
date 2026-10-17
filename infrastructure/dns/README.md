# NextDNS Multi-Account DNS Module (`infrastructure/dns`)

Manages four NextDNS accounts (`account_1`..`account_4`, 1 profile per account) declaratively via OpenTofu using `amalucelli/nextdns` (`v0.2.0`) and `carlpett/sops` (`v1.4.1`).

- **Baseline + Override Architecture:** `account_1`..`account_3` share an identical baseline posture (`local.baseline_posture`) and shared SOPS-encrypted lists (`nextdns.config.shared.{rewrites,allowlist,denylist}`). `account_4` merges per-account overrides (`nextdns.config.accounts.account_4.overrides`).
- **Provider Trade-Offs & Modernization Goal:** `amalucelli/nextdns` is currently used for complete resource coverage across security, privacy, parental control, settings, rewrites, allowlist, and denylist. `jfgmesquita/nextdns` (built on the modern `terraform-plugin-framework`) is tracked as a future drop-in replacement once its `nextdns_profile_settings` resource reaches full sub-setting parity. `Mastercard/restapi` was evaluated and rejected because the NextDNS API returns HTTP `200 OK` with `{"errors": [...]}` on user errors and requires separate sub-endpoints for nested arrays.

<!-- BEGIN_TF_DOCS -->

## Requirements

| Name                                                                     | Version   |
| ------------------------------------------------------------------------ | --------- |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | ~> 1.13.1 |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | ~> 1.13.1 |
| <a name="requirement_external"></a> [external](#requirement_external)    | 2.4.2     |
| <a name="requirement_nextdns"></a> [nextdns](#requirement_nextdns)       | 0.2.0     |
| <a name="requirement_sops"></a> [sops](#requirement_sops)                | 1.4.1     |

## Providers

| Name                                                            | Version |
| --------------------------------------------------------------- | ------- |
| <a name="provider_external"></a> [external](#provider_external) | 2.4.2   |

## Modules

| Name                                                            | Source            | Version |
| --------------------------------------------------------------- | ----------------- | ------- |
| <a name="module_account_1"></a> [account\_1](#module_account_1) | ./modules/profile | n/a     |
| <a name="module_account_2"></a> [account\_2](#module_account_2) | ./modules/profile | n/a     |
| <a name="module_account_3"></a> [account\_3](#module_account_3) | ./modules/profile | n/a     |
| <a name="module_account_4"></a> [account\_4](#module_account_4) | ./modules/profile | n/a     |
| <a name="module_account_5"></a> [account\_5](#module_account_5) | ./modules/profile | n/a     |

## Resources

| Name                                                                                                                         | Type        |
| ---------------------------------------------------------------------------------------------------------------------------- | ----------- |
| [external_external.sops_config](https://registry.terraform.io/providers/hashicorp/external/2.4.2/docs/data-sources/external) | data source |

## Inputs

| Name                                                                                                                 | Description                                                                                                                                        | Type     | Required |
| -------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | :------: |
| <a name="input_enable_prevent_destroy"></a> [enable\_prevent\_destroy](#input_enable_prevent_destroy)                | Whether to enforce prevent\_destroy on NextDNS profiles (STD-OT-44).                                                                               | `bool`   |    no    |
| <a name="input_secrets_file_path"></a> [secrets\_file\_path](#input_secrets_file_path)                               | Path to the canonical SOPS credentials file holding NextDNS credentials and sensitive profile config.                                              | `string` |    no    |
| <a name="input_state_encryption_passphrase"></a> [state\_encryption\_passphrase](#input_state_encryption_passphrase) | State and plan encryption passphrase. Source: production SOPS opentofu.state\_encryption\_passphrase. No default, so a missing value fails closed. | `string` |   yes    |

## Outputs

| Name                                                                           | Description                                                                                      |
| ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| <a name="output_account_names"></a> [account\_names](#output_account_names)    | Map of generic account keys (account\_1..account\_5) to encrypted human-readable account labels. |
| <a name="output_effective_tags"></a> [effective\_tags](#output_effective_tags) | Mandatory homelab governance tags associated with the dns root module.                           |
| <a name="output_profile_ids"></a> [profile\_ids](#output_profile_ids)          | Map of generic account keys (account\_1..account\_5) to managed NextDNS profile IDs.             |

<!-- END_TF_DOCS -->
