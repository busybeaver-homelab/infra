# Monitoring Infrastructure (`infrastructure/monitoring`)

Declarative monitoring and heartbeat check resources managed via OpenTofu and the `kristofferahl/healthchecksio` provider.

## Resources

- `healthchecksio_check.restic_backup`: Dead man's snitch heartbeat check monitoring daily restic backup execution across homelab nodes.
  - Expected ping frequency: 86400s (24 hours).
  - Grace period: 7200s (2 hours).
  - Alert channels notified when ping is missed.
- `healthchecksio_check.compose`: Per-host Docker Compose GitOps reconciler dead-man's switch and failure signal (`homelab-compose-<target>`).
  - Expected ping frequency: 900s (15 minutes).
  - Grace period: 2700s (45 minutes).

## Inputs

| Name                          | Description                                           | Type           | Sensitive |
| :---------------------------- | :---------------------------------------------------- | :------------- | :-------- |
| `healthchecksio_api_key`      | API key for Healthchecks.io account                   | `string`       | yes       |
| `default_tags`                | Default tags applied to managed checks                | `list(string)` | no        |
| `compose_targets`             | Per-host Docker Compose reconciler target identifiers | `list(string)` | yes       |
| `state_encryption_passphrase` | OpenTofu PBKDF2 state encryption passphrase           | `string`       | yes       |

## Outputs

| Name                     | Description                                                  | Sensitive |
| :----------------------- | :----------------------------------------------------------- | :-------- |
| `restic_backup_ping_url` | Unique ping endpoint for restic backup service               | yes       |
| `restic_backup_check_id` | UUID of the restic backup check                              | yes       |
| `compose_ping_urls`      | Map of compose target identifier to Healthchecks.io ping URL | yes       |

<!-- BEGIN_TF_DOCS -->

## Requirements

| Name                                                                                    | Version   |
| --------------------------------------------------------------------------------------- | --------- |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform)                | ~> 1.13.1 |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform)                | ~> 1.13.1 |
| <a name="requirement_healthchecksio"></a> [healthchecksio](#requirement_healthchecksio) | 2.3.0     |

## Providers

| Name                                                                              | Version |
| --------------------------------------------------------------------------------- | ------- |
| <a name="provider_healthchecksio"></a> [healthchecksio](#provider_healthchecksio) | 2.3.0   |

## Resources

| Name                                                                                                                                      | Type     |
| ----------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| [healthchecksio_check.backup_prune](https://registry.terraform.io/providers/kristofferahl/healthchecksio/2.3.0/docs/resources/check)      | resource |
| [healthchecksio_check.compose](https://registry.terraform.io/providers/kristofferahl/healthchecksio/2.3.0/docs/resources/check)           | resource |
| [healthchecksio_check.drift_detection](https://registry.terraform.io/providers/kristofferahl/healthchecksio/2.3.0/docs/resources/check)   | resource |
| [healthchecksio_check.gcp_restic_backup](https://registry.terraform.io/providers/kristofferahl/healthchecksio/2.3.0/docs/resources/check) | resource |
| [healthchecksio_check.oci_restic_backup](https://registry.terraform.io/providers/kristofferahl/healthchecksio/2.3.0/docs/resources/check) | resource |
| [healthchecksio_check.restic_backup](https://registry.terraform.io/providers/kristofferahl/healthchecksio/2.3.0/docs/resources/check)     | resource |

## Inputs

| Name                                                                                                                 | Description                                                                                                                                        | Type           | Default                                                         | Required |
| -------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- | --------------------------------------------------------------- | :------: |
| <a name="input_check_tags"></a> [check\_tags](#input_check_tags)                                                     | Additional project tags applied across all healthchecks (must include 'homelab').                                                                  | `list(string)` | <pre>[<br/> "homelab",<br/> "backup",<br/> "restic"<br/>]</pre> |    no    |
| <a name="input_compose_targets"></a> [compose\_targets](#input_compose_targets)                                      | Logical Docker Compose target IDs (one per host, e.g., homelab, gcp, oci-1).                                                                       | `list(string)` | <pre>[<br/> "homelab",<br/> "gcp",<br/> "oci-1"<br/>]</pre>     |    no    |
| <a name="input_default_tags"></a> [default\_tags](#input_default_tags)                                               | Default tags applied to healthchecks.                                                                                                              | `list(string)` | <pre>[<br/> "homelab",<br/> "backup",<br/> "restic"<br/>]</pre> |    no    |
| <a name="input_healthcheck_grace"></a> [healthcheck\_grace](#input_healthcheck_grace)                                | Grace period in seconds before alerting on a missed ping (300s / 5m to 14400s / 4h).                                                               | `number`       | `7200`                                                          |    no    |
| <a name="input_healthcheck_timeout"></a> [healthcheck\_timeout](#input_healthcheck_timeout)                          | Execution interval / timeout in seconds between ping events (60s to 86400s / 24h).                                                                 | `number`       | `86400`                                                         |    no    |
| <a name="input_healthchecksio_api_key"></a> [healthchecksio\_api\_key](#input_healthchecksio_api_key)                | Healthchecks.io API Key for managing checks.                                                                                                       | `string`       | n/a                                                             |   yes    |
| <a name="input_state_encryption_passphrase"></a> [state\_encryption\_passphrase](#input_state_encryption_passphrase) | State and plan encryption passphrase. Source: production SOPS opentofu.state\_encryption\_passphrase. No default, so a missing value fails closed. | `string`       | n/a                                                             |   yes    |

## Outputs

| Name                                                                                                           | Description                                                                             |
| -------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| <a name="output_backup_prune_ping_url"></a> [backup\_prune\_ping\_url](#output_backup_prune_ping_url)          | Unique ping URL for weekly Restic repository prune and integrity check dead-man switch. |
| <a name="output_compose_ping_urls"></a> [compose\_ping\_urls](#output_compose_ping_urls)                       | Map of logical compose target IDs to their unique Healthchecks.io ping URLs.            |
| <a name="output_drift_detection_ping_url"></a> [drift\_detection\_ping\_url](#output_drift_detection_ping_url) | Unique ping URL for daily OpenTofu drift detection dead-man switch.                     |
| <a name="output_gcp_restic_ping_url"></a> [gcp\_restic\_ping\_url](#output_gcp_restic_ping_url)                | Unique ping URL for GCP restic backup completion signal.                                |
| <a name="output_oci_restic_ping_url"></a> [oci\_restic\_ping\_url](#output_oci_restic_ping_url)                | Unique ping URL for OCI restic backup completion signal.                                |
| <a name="output_restic_backup_check_id"></a> [restic\_backup\_check\_id](#output_restic_backup_check_id)       | Unique UUID of the homelab restic backup check.                                         |
| <a name="output_restic_backup_ping_url"></a> [restic\_backup\_ping\_url](#output_restic_backup_ping_url)       | Unique ping URL for homelab restic backup completion signal.                            |

<!-- END_TF_DOCS -->
