<!-- BEGIN_TF_DOCS -->

## Requirements

| Name                                                                     | Version   |
| ------------------------------------------------------------------------ | --------- |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | ~> 1.13.1 |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | ~> 1.13.1 |
| <a name="requirement_external"></a> [external](#requirement_external)    | 2.4.2     |
| <a name="requirement_google"></a> [google](#requirement_google)          | 8.7.0     |
| <a name="requirement_sops"></a> [sops](#requirement_sops)                | 1.4.1     |
| <a name="requirement_tailscale"></a> [tailscale](#requirement_tailscale) | 0.29.2    |

## Providers

| Name                                                               | Version |
| ------------------------------------------------------------------ | ------- |
| <a name="provider_external"></a> [external](#provider_external)    | 2.4.2   |
| <a name="provider_google"></a> [google](#provider_google)          | 8.7.0   |
| <a name="provider_tailscale"></a> [tailscale](#provider_tailscale) | 0.29.2  |

## Resources

| Name                                                                                                                                                                  | Type        |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| [google_billing_budget.monthly_spend_limit](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/resources/billing_budget)                             | resource    |
| [google_compute_firewall.allow_breakglass_ssh](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/resources/compute_firewall)                        | resource    |
| [google_compute_firewall.allow_icmp_pmtud](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/resources/compute_firewall)                            | resource    |
| [google_compute_firewall.allow_tailscale_ingress](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/resources/compute_firewall)                     | resource    |
| [google_compute_firewall.deny_all_ingress](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/resources/compute_firewall)                            | resource    |
| [google_compute_instance.default](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/resources/compute_instance)                                     | resource    |
| [google_compute_network.default_vpc](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/resources/compute_network)                                   | resource    |
| [google_compute_subnetwork.private](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/resources/compute_subnetwork)                                 | resource    |
| [google_monitoring_notification_channel.budget_email](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/resources/monitoring_notification_channel)  | resource    |
| [google_project_iam_custom_role.backup_append_only](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/resources/project_iam_custom_role)            | resource    |
| [google_project_iam_custom_role.backup_pruner](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/resources/project_iam_custom_role)                 | resource    |
| [google_service_account.backup_pruner](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/resources/service_account)                                 | resource    |
| [google_service_account.backup_writer](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/resources/service_account)                                 | resource    |
| [google_service_account.vm](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/resources/service_account)                                            | resource    |
| [google_storage_bucket.backups](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/resources/storage_bucket)                                         | resource    |
| [google_storage_bucket_iam_member.backup_pruner](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/resources/storage_bucket_iam_member)             | resource    |
| [google_storage_bucket_iam_member.backup_writer_append_only](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/resources/storage_bucket_iam_member) | resource    |
| [google_storage_hmac_key.backup_pruner](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/resources/storage_hmac_key)                               | resource    |
| [google_storage_hmac_key.backup_writer](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/resources/storage_hmac_key)                               | resource    |
| [tailscale_federated_identity.gcp_vm](https://registry.terraform.io/providers/tailscale/tailscale/0.29.2/docs/resources/federated_identity)                           | resource    |
| [external_external.sops_config](https://registry.terraform.io/providers/hashicorp/external/2.4.2/docs/data-sources/external)                                          | data source |
| [google_compute_image.ubuntu_2604](https://registry.terraform.io/providers/hashicorp/google/8.7.0/docs/data-sources/compute_image)                                    | data source |

## Inputs

| Name                                                                                                                 | Description                                                                                                                                        | Type           | Required |
| -------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- | :------: |
| <a name="input_admin_cidr"></a> [admin\_cidr](#input_admin_cidr)                                                     | Optional emergency breakglass IPv4 CIDR block for TCP/22 ingress. Leave null in steady state.                                                      | `string`       |    no    |
| <a name="input_budget_alert_recipients"></a> [budget\_alert\_recipients](#input_budget_alert_recipients)             | Optional list of email addresses to receive GCP budget alert notifications (overrides SOPS gcp.config.budget\_alert\_recipients if non-empty).     | `list(string)` |    no    |
| <a name="input_default_labels"></a> [default\_labels](#input_default_labels)                                         | Default labels applied to all GCP resources. Must include project = 'homelab'.                                                                     | `map(string)`  |    no    |
| <a name="input_enable_prevent_destroy"></a> [enable\_prevent\_destroy](#input_enable_prevent_destroy)                | Whether to prevent destruction of critical compute and backup resources.                                                                           | `bool`         |    no    |
| <a name="input_gcp_billing_account_id"></a> [gcp\_billing\_account\_id](#input_gcp_billing_account_id)               | The GCP billing account ID (e.g., 012345-6789AB-CDEF01) for mandatory $1 budget and spend alert management.                                        | `string`       |   yes    |
| <a name="input_gcp_boot_disk_size_gb"></a> [gcp\_boot\_disk\_size\_gb](#input_gcp_boot_disk_size_gb)                 | The boot disk size in GB. Strictly restricted to the Always Free Tier allowance: 10 to 30 GB.                                                      | `number`       |    no    |
| <a name="input_gcp_boot_disk_type"></a> [gcp\_boot\_disk\_type](#input_gcp_boot_disk_type)                           | The persistent disk type. Strictly restricted to the Always Free Tier type: pd-standard.                                                           | `string`       |    no    |
| <a name="input_gcp_instance_type"></a> [gcp\_instance\_type](#input_gcp_instance_type)                               | The GCP compute instance machine type. Strictly restricted to the Always Free Tier shape: e2-micro.                                                | `string`       |    no    |
| <a name="input_gcp_network_tier"></a> [gcp\_network\_tier](#input_gcp_network_tier)                                  | Network Service Tier for the external IPv4 access config. Strictly restricted to STANDARD.                                                         | `string`       |    no    |
| <a name="input_gcp_project_id"></a> [gcp\_project\_id](#input_gcp_project_id)                                        | The Google Cloud project ID.                                                                                                                       | `string`       |   yes    |
| <a name="input_gcp_region"></a> [gcp\_region](#input_gcp_region)                                                     | The primary Google Cloud region. Must be in the GCP Always Free Tier eligible regions: us-central1, us-east1, us-west1.                            | `string`       |    no    |
| <a name="input_gcp_zone"></a> [gcp\_zone](#input_gcp_zone)                                                           | The Google Cloud availability zone within gcp\_region (e.g., us-central1-a).                                                                       | `string`       |    no    |
| <a name="input_secrets_file_path"></a> [secrets\_file\_path](#input_secrets_file_path)                               | Path to the canonical SOPS credentials file (defaults to production credentials).                                                                  | `string`       |    no    |
| <a name="input_state_encryption_passphrase"></a> [state\_encryption\_passphrase](#input_state_encryption_passphrase) | State and plan encryption passphrase. Source: production SOPS opentofu.state\_encryption\_passphrase. No default, so a missing value fails closed. | `string`       |   yes    |
| <a name="input_tailscale_bootstrap_tags"></a> [tailscale\_bootstrap\_tags](#input_tailscale_bootstrap_tags)          | Tailscale tags assigned to the GCP workload identity federation trust for gcp-default-vm.                                                          | `list(string)` |    no    |
| <a name="input_vpc_subnet_cidr"></a> [vpc\_subnet\_cidr](#input_vpc_subnet_cidr)                                     | IPv4 CIDR block for the private GCP compute subnetwork (sourced from SOPS gcp.subnet\_cidr when null).                                             | `string`       |    no    |

## Outputs

| Name                                                                                                                     | Description                                                                                           |
| ------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| <a name="output_ansible_inventory"></a> [ansible\_inventory](#output_ansible_inventory)                                  | Structured Ansible inventory map for GCP compute instances consumed by scripts/generate-inventory.sh. |
| <a name="output_backup_bucket_name"></a> [backup\_bucket\_name](#output_backup_bucket_name)                              | Name of the GCS regional Standard bucket for primary Restic backups.                                  |
| <a name="output_backup_hmac_access_id"></a> [backup\_hmac\_access\_id](#output_backup_hmac_access_id)                    | HMAC access ID for the append-only backup writer service account.                                     |
| <a name="output_backup_hmac_secret"></a> [backup\_hmac\_secret](#output_backup_hmac_secret)                              | HMAC secret key for the append-only backup writer service account.                                    |
| <a name="output_backup_prune_hmac_access_id"></a> [backup\_prune\_hmac\_access\_id](#output_backup_prune_hmac_access_id) | HMAC access ID for the dedicated backup pruner service account.                                       |
| <a name="output_backup_prune_hmac_secret"></a> [backup\_prune\_hmac\_secret](#output_backup_prune_hmac_secret)           | HMAC secret key for the dedicated backup pruner service account.                                      |
| <a name="output_backup_s3_endpoint"></a> [backup\_s3\_endpoint](#output_backup_s3_endpoint)                              | S3-compatible endpoint URL for GCS Restic backups.                                                    |
| <a name="output_budget_name"></a> [budget\_name](#output_budget_name)                                                    | Resource name of the mandatory $1 monthly GCP billing budget.                                         |
| <a name="output_instance_id"></a> [instance\_id](#output_instance_id)                                                    | The unique instance ID of gcp-default-vm.                                                             |
| <a name="output_instance_name"></a> [instance\_name](#output_instance_name)                                              | The hostname of the GCP compute instance.                                                             |
| <a name="output_instance_private_ip"></a> [instance\_private\_ip](#output_instance_private_ip)                           | The internal RFC1918 IPv4 address of gcp-default-vm.                                                  |
| <a name="output_instance_public_ip"></a> [instance\_public\_ip](#output_instance_public_ip)                              | The Standard-Tier ephemeral external IPv4 address of gcp-default-vm.                                  |
| <a name="output_subnet_id"></a> [subnet\_id](#output_subnet_id)                                                          | The ID of the private GCP compute subnetwork.                                                         |
| <a name="output_vm_service_account_email"></a> [vm\_service\_account\_email](#output_vm_service_account_email)           | Email of the dedicated least-privilege VM service account.                                            |
| <a name="output_vpc_network_id"></a> [vpc\_network\_id](#output_vpc_network_id)                                          | The ID of the GCP VPC network.                                                                        |
| <a name="output_vpc_network_name"></a> [vpc\_network\_name](#output_vpc_network_name)                                    | The name of the GCP VPC network.                                                                      |

<!-- END_TF_DOCS -->
