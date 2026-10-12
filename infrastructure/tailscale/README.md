<!-- BEGIN_TF_DOCS -->

## Requirements

| Name                                                                     | Version   |
| ------------------------------------------------------------------------ | --------- |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | 1.16.5    |
| <a name="requirement_sops"></a> [sops](#requirement_sops)                | 1.4.1     |
| <a name="requirement_tailscale"></a> [tailscale](#requirement_tailscale) | ~> 0.29.2 |

## Providers

| Name                                                               | Version |
| ------------------------------------------------------------------ | ------- |
| <a name="provider_sops"></a> [sops](#provider_sops)                | 1.4.1   |
| <a name="provider_tailscale"></a> [tailscale](#provider_tailscale) | 0.29.2  |

## Resources

| Name                                                                                                                                              | Type        |
| ------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| [tailscale_acl.homelab](https://registry.terraform.io/providers/tailscale/tailscale/latest/docs/resources/acl)                                    | resource    |
| [tailscale_contacts.homelab](https://registry.terraform.io/providers/tailscale/tailscale/latest/docs/resources/contacts)                          | resource    |
| [tailscale_dns_nameservers.homelab](https://registry.terraform.io/providers/tailscale/tailscale/latest/docs/resources/dns_nameservers)            | resource    |
| [tailscale_dns_preferences.homelab](https://registry.terraform.io/providers/tailscale/tailscale/latest/docs/resources/dns_preferences)            | resource    |
| [tailscale_dns_search_paths.homelab](https://registry.terraform.io/providers/tailscale/tailscale/latest/docs/resources/dns_search_paths)          | resource    |
| [tailscale_dns_split_nameservers.routes](https://registry.terraform.io/providers/tailscale/tailscale/latest/docs/resources/dns_split_nameservers) | resource    |
| [tailscale_tailnet_key.bootstrap](https://registry.terraform.io/providers/tailscale/tailscale/latest/docs/resources/tailnet_key)                  | resource    |
| [tailscale_tailnet_key.roles](https://registry.terraform.io/providers/tailscale/tailscale/latest/docs/resources/tailnet_key)                      | resource    |
| [tailscale_tailnet_settings.homelab](https://registry.terraform.io/providers/tailscale/tailscale/latest/docs/resources/tailnet_settings)          | resource    |
| [sops_file.secrets](https://registry.terraform.io/providers/carlpett/sops/1.4.1/docs/data-sources/file)                                           | data source |
| [tailscale_device.monitored](https://registry.terraform.io/providers/tailscale/tailscale/latest/docs/data-sources/device)                         | data source |
| [tailscale_devices.all](https://registry.terraform.io/providers/tailscale/tailscale/latest/docs/data-sources/devices)                             | data source |
| [tailscale_users.all](https://registry.terraform.io/providers/tailscale/tailscale/latest/docs/data-sources/users)                                 | data source |

## Inputs

| Name                                                                                                                 | Description                                                                              | Type                                                                                                                                                                          | Default                                                                                                                               | Required |
| -------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | :------: |
| <a name="input_auth_keys"></a> [auth\_keys](#input_auth_keys)                                                        | Map of role-specific authentication keys to manage declaratively.                        | <pre>map(object({<br/> reusable = bool<br/> ephemeral = bool<br/> preauthorized = bool<br/> expiry = number<br/> description = string<br/> tags = list(string)<br/> }))</pre> | `{}`                                                                                                                                  |    no    |
| <a name="input_bootstrap_key_tags"></a> [bootstrap\_key\_tags](#input_bootstrap_key_tags)                            | Tailscale tags assigned to the bootstrap authentication key.                             | `list(string)`                                                                                                                                                                | <pre>[<br/> "tag:type-server",<br/> "tag:os-linux",<br/> "tag:hosting-cloud",<br/> "tag:location-ger",<br/> "tag:env-oci"<br/>]</pre> |    no    |
| <a name="input_dns_nameservers"></a> [dns\_nameservers](#input_dns_nameservers)                                      | List of global DNS nameservers for the tailnet.                                          | `list(string)`                                                                                                                                                                | `[]`                                                                                                                                  |    no    |
| <a name="input_dns_search_paths"></a> [dns\_search\_paths](#input_dns_search_paths)                                  | List of search domains for MagicDNS.                                                     | `list(string)`                                                                                                                                                                | `[]`                                                                                                                                  |    no    |
| <a name="input_dns_split_nameservers"></a> [dns\_split\_nameservers](#input_dns_split_nameservers)                   | Map of domain routes to dedicated split DNS nameservers.                                 | `map(list(string))`                                                                                                                                                           | `{}`                                                                                                                                  |    no    |
| <a name="input_monitored_device_hostnames"></a> [monitored\_device\_hostnames](#input_monitored_device_hostnames)    | List of device hostnames (without domain suffix) to retrieve via data.tailscale\_device. | `list(string)`                                                                                                                                                                | <pre>[<br/> "unifi-gateway",<br/> "adguard-home"<br/>]</pre>                                                                          |    no    |
| <a name="input_policy_file_path"></a> [policy\_file\_path](#input_policy_file_path)                                  | Path to Tailscale ACL HuJSON policy file.                                                | `string`                                                                                                                                                                      | `"policy.hujson"`                                                                                                                     |    no    |
| <a name="input_secrets_file_path"></a> [secrets\_file\_path](#input_secrets_file_path)                               | Path to the canonical SOPS credentials file holding tailscale credentials.               | `string`                                                                                                                                                                      | `"../../secrets/credentials.sops.yaml"`                                                                                               |    no    |
| <a name="input_state_encryption_passphrase"></a> [state\_encryption\_passphrase](#input_state_encryption_passphrase) | Passphrase for OpenTofu state and plan encryption.                                       | `string`                                                                                                                                                                      | `"homelab-state-encryption-passphrase-default"`                                                                                       |    no    |
| <a name="input_tailnet_name"></a> [tailnet\_name](#input_tailnet_name)                                               | Tailscale tailnet name (overrides SOPS if provided).                                     | `string`                                                                                                                                                                      | `""`                                                                                                                                  |    no    |
| <a name="input_tailscale_client_id"></a> [tailscale\_client\_id](#input_tailscale_client_id)                         | Tailscale OAuth client ID (overrides SOPS if provided).                                  | `string`                                                                                                                                                                      | `""`                                                                                                                                  |    no    |
| <a name="input_tailscale_client_secret"></a> [tailscale\_client\_secret](#input_tailscale_client_secret)             | Tailscale OAuth client secret (overrides SOPS if provided).                              | `string`                                                                                                                                                                      | `""`                                                                                                                                  |    no    |

## Outputs

| Name                                                                                        | Description                                                              |
| ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| <a name="output_auth_key_bootstrap"></a> [auth\_key\_bootstrap](#output_auth_key_bootstrap) | Bootstrap authentication key for node provisioning.                      |
| <a name="output_devices"></a> [devices](#output_devices)                                    | All enrolled Tailscale devices in the tailnet.                           |
| <a name="output_monitored_devices"></a> [monitored\_devices](#output_monitored_devices)     | Map of monitored Tailscale devices retrieved via data.tailscale\_device. |
| <a name="output_role_auth_keys"></a> [role\_auth\_keys](#output_role_auth_keys)             | Generated role-specific Tailscale authentication keys.                   |
| <a name="output_users"></a> [users](#output_users)                                          | All users enrolled in the Tailscale tailnet.                             |

<!-- END_TF_DOCS -->
