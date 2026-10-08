# Monitoring Infrastructure (`infrastructure/monitoring`)

Declarative monitoring and heartbeat check resources managed via OpenTofu and the `kristofferahl/healthchecksio` provider.

## Resources

- `healthchecksio_check.restic_backup`: Dead man's snitch heartbeat check monitoring daily restic backup execution across homelab nodes.
  - Expected ping frequency: 86400s (24 hours).
  - Grace period: 7200s (2 hours).
  - Alert channels notified when ping is missed.

## Inputs

| Name                          | Description                                 | Type           | Sensitive |
| :---------------------------- | :------------------------------------------ | :------------- | :-------- |
| `healthchecksio_api_key`      | API key for Healthchecks.io account         | `string`       | yes       |
| `default_tags`                | Default tags applied to managed checks      | `list(string)` | no        |
| `state_encryption_passphrase` | OpenTofu PBKDF2 state encryption passphrase | `string`       | yes       |

## Outputs

| Name                     | Description                                    | Sensitive |
| :----------------------- | :--------------------------------------------- | :-------- |
| `restic_backup_ping_url` | Unique ping endpoint for restic backup service | yes       |
| `restic_backup_check_id` | UUID of the restic backup check                | yes       |

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8.0 |
| <a name="requirement_healthchecksio"></a> [healthchecksio](#requirement\_healthchecksio) | ~> 2.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_healthchecksio"></a> [healthchecksio](#provider\_healthchecksio) | 2.3.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [healthchecksio_check.restic_backup](https://registry.terraform.io/providers/kristofferahl/healthchecksio/latest/docs/resources/check) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Default tags applied to healthchecks. | `list(string)` | <pre>[<br/>  "homelab",<br/>  "backup",<br/>  "restic"<br/>]</pre> | no |
| <a name="input_healthchecksio_api_key"></a> [healthchecksio\_api\_key](#input\_healthchecksio\_api\_key) | Healthchecks.io API Key for managing checks. | `string` | n/a | yes |
| <a name="input_state_encryption_passphrase"></a> [state\_encryption\_passphrase](#input\_state\_encryption\_passphrase) | Passphrase for OpenTofu state and plan encryption. | `string` | `"homelab-state-encryption-passphrase-default"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_restic_backup_check_id"></a> [restic\_backup\_check\_id](#output\_restic\_backup\_check\_id) | Unique UUID of the homelab restic backup check. |
| <a name="output_restic_backup_ping_url"></a> [restic\_backup\_ping\_url](#output\_restic\_backup\_ping\_url) | Unique ping URL for homelab restic backup completion signal. |
<!-- END_TF_DOCS -->
