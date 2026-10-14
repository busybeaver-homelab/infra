# Cloudflare

Account- and zone-level Cloudflare configuration. Identifying values (zone name, records,
addresses, IDs, WAF expressions, Zero Trust auth domain) are read at plan time from
`secrets/credentials.sops.yaml` → `cloudflare.config` via `data.sops_file`; this directory
contains only structure and non-identifying posture.

## Layout

| File                         | Manages                                                                                      |
| ---------------------------- | -------------------------------------------------------------------------------------------- |
| `account.tf`                 | Account settings (2FA enforcement)                                                           |
| `r2.tf`                      | R2 buckets (state, DR backups)                                                               |
| `zero_trust.tf`              | Access organization, OTP IdP, Gateway settings, default DNS location, default device profile |
| `notifications.tf`           | Email notification policies (excluding budget alert, managed via sync script)                |
| `email_routing_addresses.tf` | Email Routing destination addresses                                                          |
| `iam_frozen.tf`              | **Frozen** account tokens and member (documentation only; token policies live in SOPS)       |
| `zones.tf` → `modules/zone`  | Per-zone: zone, DNSSEC, settings, DNS, Email Routing, WAF custom rules, bot management       |

## Frozen resources

`cloudflare_account_token.frozen[*]` and `cloudflare_account_member.frozen` use
`prevent_destroy = true` and `ignore_changes = all`: OpenTofu never modifies them, and drift
on them is **not** reported. `tests/scripts/cloudflare-guards.bats` fails if the guards are removed.
Because `ignore_changes`/`prevent_destroy` do not stop _creation_, each frozen token carries a
precondition: if it was deleted outside OpenTofu, plan fails instead of minting a new token. Remove it
from `local.frozen_token_names` and `tofu state rm` it instead.

## Editing DNS records and Email Routing rules

Edit `cloudflare.config.zones.<zone_key>` with `sops`. Map keys (`a_1`, `rule_01`, ...) are resource
addresses: **never renumber or rename them**, or OpenTofu destroys and recreates the object. New
entries need no `id` (it was only used for the one-time import). Email-Routing-owned MX and DKIM
records are rejected by validation (its apex SPF cannot be told apart from custom SPF by content).

## Drift detection

CI cannot decrypt production SOPS, so this module is excluded from
`.github/workflows/drift-detection.yml`. Run `mise run drift:cloudflare` locally: it prints counts and
addresses only and exits `0` (no drift), `2` (drift) or `1` (error).

## Adding a zone

> **Module assumption:** `modules/zone` always manages Email Routing (settings + catch-all), DNSSEC
> (`active`) and Bot Fight Mode for every zone. A zone that should _not_ use these needs the module
> extended first (make them optional per zone with `count`, plus `moved` blocks for the existing
> `primary` addresses). Per-zone setting overrides (`zone_settings_overrides`) are not yet wired
> through `zones.tf`.

1. Add `cloudflare.config.zones.<logical_key>` to **both** SOPS files: real values in
   `credentials.sops.yaml`, decoy leaves with identical key paths in `credentials.ci.sops.yaml`.
   Logical keys (zone key, record keys such as `a_1`) must be non-identifying because SOPS does not
   encrypt keys, and must never be renumbered: a changed key destroys and recreates that object.
2. Add a temporary `imports.tf` with one `import {}` block per existing object of the new zone
   (zone, DNSSEC, each `cloudflare_zone_setting`, DNS record, Email Routing settings/rule/catch-all,
   WAF ruleset, bot management), targeting `module.zone["<logical_key>"]...`. Import IDs come from
   `local.cf` and must be wrapped in `nonsensitive()`; keep plan output out of logs and chat.
3. Iterate `tofu plan` until it shows only imports (0 add / 0 change / 0 destroy), apply, confirm a
   follow-up plan reports _No changes_, then delete `imports.tf` (the guard test enforces this).

## Not managed (and why)

- **Workers account subdomain**: no resource in provider v5.27.
- **`billing_budget_alert` notification**: its `total_spend_dollars` filter is not in the v5.27 schema; synchronized out-of-band to the platform minimum ($1 USD) via `mise run sync:cloudflare:budget`.
- **`billing_usage_alert` notification**: requires product/limit filters; spending is protected globally by `billing_budget_alert`.
- **Email-Routing-owned DNS records** (MX/SPF/DKIM): owned by Email Routing; rejected by module validation.
- **Email Routing catch-all as a rule**: managed only via `cloudflare_email_routing_catch_all`.
- **Page Rules**: none exist (verified 2026-10-09).
- **Defaults-only areas**: managed rulesets, universal SSL, managed headers, URL normalization, tiered cache, page shield, leaked-credential checks, DNS zone settings, security.txt.
- **Authenticated Origin Pulls settings resource**: managed through zone setting `tls_client_auth` instead.
- **Gateway `activity_log`, `block_page`, `fips`**: unset (null) live; not representable without a change, so not managed.
- **Access organization `service_token_inactivity`**: disabled live with null action/threshold, which the v5.27 schema cannot express; excluded via `ignore_changes`.
- **Second zone in the account**: out of scope (see "Adding a zone").

<!-- BEGIN_TF_DOCS -->

## Requirements

| Name                                                                        | Version |
| --------------------------------------------------------------------------- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform)    | 1.16.6  |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement_cloudflare) | 5.28.0  |
| <a name="requirement_sops"></a> [sops](#requirement_sops)                   | 1.4.1   |

## Providers

| Name                                                                  | Version |
| --------------------------------------------------------------------- | ------- |
| <a name="provider_cloudflare"></a> [cloudflare](#provider_cloudflare) | 5.28.0  |
| <a name="provider_sops"></a> [sops](#provider_sops)                   | 1.4.1   |

## Modules

| Name                                            | Source         | Version |
| ----------------------------------------------- | -------------- | ------- |
| <a name="module_zone"></a> [zone](#module_zone) | ./modules/zone | n/a     |

## Resources

| Name                                                                                                                                                                                       | Type        |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------- |
| [cloudflare_account.this](https://registry.terraform.io/providers/cloudflare/cloudflare/5.28.0/docs/resources/account)                                                                     | resource    |
| [cloudflare_account_member.frozen](https://registry.terraform.io/providers/cloudflare/cloudflare/5.28.0/docs/resources/account_member)                                                     | resource    |
| [cloudflare_account_token.frozen](https://registry.terraform.io/providers/cloudflare/cloudflare/5.28.0/docs/resources/account_token)                                                       | resource    |
| [cloudflare_email_routing_address.this](https://registry.terraform.io/providers/cloudflare/cloudflare/5.28.0/docs/resources/email_routing_address)                                         | resource    |
| [cloudflare_notification_policy.this](https://registry.terraform.io/providers/cloudflare/cloudflare/5.28.0/docs/resources/notification_policy)                                             | resource    |
| [cloudflare_r2_bucket.backups_dr](https://registry.terraform.io/providers/cloudflare/cloudflare/5.28.0/docs/resources/r2_bucket)                                                           | resource    |
| [cloudflare_r2_bucket.tfstate](https://registry.terraform.io/providers/cloudflare/cloudflare/5.28.0/docs/resources/r2_bucket)                                                              | resource    |
| [cloudflare_zero_trust_access_identity_provider.otp](https://registry.terraform.io/providers/cloudflare/cloudflare/5.28.0/docs/resources/zero_trust_access_identity_provider)              | resource    |
| [cloudflare_zero_trust_device_default_profile.this](https://registry.terraform.io/providers/cloudflare/cloudflare/5.28.0/docs/resources/zero_trust_device_default_profile)                 | resource    |
| [cloudflare_zero_trust_dns_location.default](https://registry.terraform.io/providers/cloudflare/cloudflare/5.28.0/docs/resources/zero_trust_dns_location)                                  | resource    |
| [cloudflare_zero_trust_gateway_settings.this](https://registry.terraform.io/providers/cloudflare/cloudflare/5.28.0/docs/resources/zero_trust_gateway_settings)                             | resource    |
| [cloudflare_zero_trust_organization.this](https://registry.terraform.io/providers/cloudflare/cloudflare/5.28.0/docs/resources/zero_trust_organization)                                     | resource    |
| [cloudflare_account_api_token_permission_groups_list.all](https://registry.terraform.io/providers/cloudflare/cloudflare/5.28.0/docs/data-sources/account_api_token_permission_groups_list) | data source |
| [cloudflare_account_permission_groups.frozen_member](https://registry.terraform.io/providers/cloudflare/cloudflare/5.28.0/docs/data-sources/account_permission_groups)                     | data source |
| [cloudflare_account_tokens.all](https://registry.terraform.io/providers/cloudflare/cloudflare/5.28.0/docs/data-sources/account_tokens)                                                     | data source |
| [sops_file.secrets](https://registry.terraform.io/providers/carlpett/sops/1.4.1/docs/data-sources/file)                                                                                    | data source |

## Inputs

| Name                                                                                                                 | Description                                                                                                                                        | Type     | Default                                 | Required |
| -------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | --------------------------------------- | :------: |
| <a name="input_cloudflare_account_id"></a> [cloudflare\_account\_id](#input_cloudflare_account_id)                   | The Cloudflare account ID for managing R2 and account-level resources.                                                                             | `string` | n/a                                     |   yes    |
| <a name="input_cloudflare_api_token"></a> [cloudflare\_api\_token](#input_cloudflare_api_token)                      | The API token for authenticating with Cloudflare.                                                                                                  | `string` | n/a                                     |   yes    |
| <a name="input_enable_prevent_destroy"></a> [enable\_prevent\_destroy](#input_enable_prevent_destroy)                | Whether to prevent destruction of critical Cloudflare resources (defaults to true for production safety).                                          | `bool`   | `true`                                  |    no    |
| <a name="input_r2_backup_bucket_name"></a> [r2\_backup\_bucket\_name](#input_r2_backup_bucket_name)                  | The name of the Cloudflare R2 bucket for disaster recovery backups.                                                                                | `string` | `"homelab-backups-dr"`                  |    no    |
| <a name="input_r2_backup_location"></a> [r2\_backup\_location](#input_r2_backup_location)                            | Location hint for the R2 disaster recovery backup bucket.                                                                                          | `string` | `"weur"`                                |    no    |
| <a name="input_secrets_file_path"></a> [secrets\_file\_path](#input_secrets_file_path)                               | Path to the canonical SOPS credentials file holding cloudflare.config (defaults to production credentials).                                        | `string` | `"../../secrets/credentials.sops.yaml"` |    no    |
| <a name="input_state_encryption_passphrase"></a> [state\_encryption\_passphrase](#input_state_encryption_passphrase) | State and plan encryption passphrase. Source: production SOPS opentofu.state\_encryption\_passphrase. No default, so a missing value fails closed. | `string` | n/a                                     |   yes    |

## Outputs

| Name                                                                                                     | Description                                                   |
| -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| <a name="output_managed_zone_keys"></a> [managed\_zone\_keys](#output_managed_zone_keys)                 | Logical keys of the zones managed by this module.             |
| <a name="output_r2_backup_bucket_name"></a> [r2\_backup\_bucket\_name](#output_r2_backup_bucket_name)    | The name of the secondary R2 disaster recovery backup bucket. |
| <a name="output_r2_backup_endpoint"></a> [r2\_backup\_endpoint](#output_r2_backup_endpoint)              | S3-compatible endpoint URL for the R2 backup bucket.          |
| <a name="output_r2_tfstate_bucket_name"></a> [r2\_tfstate\_bucket\_name](#output_r2_tfstate_bucket_name) | The name of the OpenTofu state storage R2 bucket.             |
| <a name="output_zone_ids"></a> [zone\_ids](#output_zone_ids)                                             | Cloudflare zone IDs keyed by logical zone key.                |

<!-- END_TF_DOCS -->
