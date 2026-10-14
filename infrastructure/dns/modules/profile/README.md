# NextDNS Profile Child Module (`infrastructure/dns/modules/profile`)

Reusable OpenTofu child module managing a single NextDNS profile and all 7 sub-resources (`nextdns_security`, `nextdns_privacy`, `nextdns_parental_control`, `nextdns_settings`, `nextdns_rewrite`, `nextdns_allowlist`, and `nextdns_denylist`) for a single provider alias.

<!-- BEGIN_TF_DOCS -->

## Requirements

| Name                                                                     | Version   |
| ------------------------------------------------------------------------ | --------- |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | ~> 1.13.1 |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | ~> 1.13.1 |
| <a name="requirement_nextdns"></a> [nextdns](#requirement_nextdns)       | 0.2.0     |

## Providers

| Name                                                         | Version |
| ------------------------------------------------------------ | ------- |
| <a name="provider_nextdns"></a> [nextdns](#provider_nextdns) | 0.2.0   |

## Resources

| Name                                                                                                                              | Type     |
| --------------------------------------------------------------------------------------------------------------------------------- | -------- |
| [nextdns_allowlist.this](https://registry.terraform.io/providers/amalucelli/nextdns/0.2.0/docs/resources/allowlist)               | resource |
| [nextdns_denylist.this](https://registry.terraform.io/providers/amalucelli/nextdns/0.2.0/docs/resources/denylist)                 | resource |
| [nextdns_parental_control.this](https://registry.terraform.io/providers/amalucelli/nextdns/0.2.0/docs/resources/parental_control) | resource |
| [nextdns_privacy.this](https://registry.terraform.io/providers/amalucelli/nextdns/0.2.0/docs/resources/privacy)                   | resource |
| [nextdns_profile.this](https://registry.terraform.io/providers/amalucelli/nextdns/0.2.0/docs/resources/profile)                   | resource |
| [nextdns_rewrite.this](https://registry.terraform.io/providers/amalucelli/nextdns/0.2.0/docs/resources/rewrite)                   | resource |
| [nextdns_security.this](https://registry.terraform.io/providers/amalucelli/nextdns/0.2.0/docs/resources/security)                 | resource |
| [nextdns_settings.this](https://registry.terraform.io/providers/amalucelli/nextdns/0.2.0/docs/resources/settings)                 | resource |

## Inputs

| Name                                                                                                  | Description                                                                                  | Type                                                                                                                                                                                                                                                                                                                                                                     | Default | Required |
| ----------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------- | :------: |
| <a name="input_allowlist"></a> [allowlist](#input_allowlist)                                          | Sensitive allowlist domain entries for the NextDNS profile.                                  | <pre>list(object({<br/> id = string<br/> active = bool<br/> }))</pre>                                                                                                                                                                                                                                                                                                    | `[]`    |    no    |
| <a name="input_denylist"></a> [denylist](#input_denylist)                                             | Sensitive denylist domain entries for the NextDNS profile.                                   | <pre>list(object({<br/> id = string<br/> active = bool<br/> }))</pre>                                                                                                                                                                                                                                                                                                    | `[]`    |    no    |
| <a name="input_enable_prevent_destroy"></a> [enable\_prevent\_destroy](#input_enable_prevent_destroy) | Whether to enforce prevent\_destroy on nextdns\_profile.this (STD-OT-44).                    | `bool`                                                                                                                                                                                                                                                                                                                                                                   | `true`  |    no    |
| <a name="input_parental_control"></a> [parental\_control](#input_parental_control)                    | Parental control settings, blocked categories, and blocked services for the NextDNS profile. | <pre>object({<br/> safe_search = bool<br/> youtube_restricted_mode = bool<br/> block_bypass = bool<br/> categories = list(object({<br/> id = string<br/> active = bool<br/> recreation = bool<br/> }))<br/> services = list(object({<br/> id = string<br/> active = bool<br/> recreation = bool<br/> }))<br/> })</pre>                                                   | n/a     |   yes    |
| <a name="input_privacy"></a> [privacy](#input_privacy)                                                | Privacy blocklists, native tracker lists, and CNAME/affiliate flags for the NextDNS profile. | <pre>object({<br/> disguised_trackers = bool<br/> allow_affiliate = bool<br/> blocklists = list(string)<br/> natives = list(string)<br/> })</pre>                                                                                                                                                                                                                        | n/a     |   yes    |
| <a name="input_profile_name"></a> [profile\_name](#input_profile_name)                                | Display name of the NextDNS profile (sensitive per AGENTS.md).                               | `string`                                                                                                                                                                                                                                                                                                                                                                 | n/a     |   yes    |
| <a name="input_rewrites"></a> [rewrites](#input_rewrites)                                             | Sensitive DNS rewrites (domain -> IP/target) for the NextDNS profile.                        | <pre>list(object({<br/> name = string<br/> content = string<br/> }))</pre>                                                                                                                                                                                                                                                                                               | `[]`    |    no    |
| <a name="input_security"></a> [security](#input_security)                                             | Security threat protection settings and blocked TLDs for the NextDNS profile.                | <pre>object({<br/> threat_intelligence_feeds = bool<br/> ai_threat_detection = bool<br/> google_safe_browsing = bool<br/> cryptojacking = bool<br/> dns_rebinding = bool<br/> idn_homographs = bool<br/> typosquatting = bool<br/> dga = bool<br/> nrd = bool<br/> ddns = bool<br/> parking = bool<br/> csam = bool<br/> tlds = list(string)<br/> })</pre>               | n/a     |   yes    |
| <a name="input_settings"></a> [settings](#input_settings)                                             | Operational settings (logs, block\_page, performance, bav, web3) for the NextDNS profile.    | <pre>object({<br/> bav = bool<br/> web3 = bool<br/> logs = object({<br/> enabled = bool<br/> drop_ip = bool<br/> drop_domain = bool<br/> retention = string<br/> location = string<br/> })<br/> block_page = object({<br/> enabled = bool<br/> })<br/> performance = object({<br/> ecs = bool<br/> cache_boost = bool<br/> cname_flattening = bool<br/> })<br/> })</pre> | n/a     |   yes    |

## Outputs

| Name                                                                                    | Description                                                               |
| --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| <a name="output_allowlist_enabled"></a> [allowlist\_enabled](#output_allowlist_enabled) | Whether the nextdns\_allowlist resource is instantiated for this profile. |
| <a name="output_denylist_enabled"></a> [denylist\_enabled](#output_denylist_enabled)    | Whether the nextdns\_denylist resource is instantiated for this profile.  |
| <a name="output_profile_id"></a> [profile\_id](#output_profile_id)                      | The 6-character NextDNS profile ID.                                       |
| <a name="output_rewrite_enabled"></a> [rewrite\_enabled](#output_rewrite_enabled)       | Whether the nextdns\_rewrite resource is instantiated for this profile.   |

<!-- END_TF_DOCS -->
