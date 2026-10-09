<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8.0 |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement\_cloudflare) | ~> 5.27 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_cloudflare"></a> [cloudflare](#provider\_cloudflare) | ~> 5.27 |

## Resources

| Name | Type |
| ---- | ---- |
| [cloudflare_bot_management.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/bot_management) | resource |
| [cloudflare_dns_record.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/dns_record) | resource |
| [cloudflare_email_routing_catch_all.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/email_routing_catch_all) | resource |
| [cloudflare_email_routing_rule.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/email_routing_rule) | resource |
| [cloudflare_email_routing_settings.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/email_routing_settings) | resource |
| [cloudflare_ruleset.waf_custom](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/ruleset) | resource |
| [cloudflare_zone.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zone) | resource |
| [cloudflare_zone_dnssec.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zone_dnssec) | resource |
| [cloudflare_zone_setting.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zone_setting) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | Cloudflare account ID owning the zone. | `string` | n/a | yes |
| <a name="input_zone"></a> [zone](#input\_zone) | Identifying zone data decoded from SOPS (cloudflare.config.zones.<key>). | <pre>object({<br/>    name = string<br/>    id   = string<br/>    dns_records = map(object({<br/>      id       = string<br/>      type     = string<br/>      name     = string<br/>      content  = string<br/>      ttl      = number<br/>      proxied  = bool<br/>      priority = optional(number)<br/>      comment  = optional(string)<br/>    }))<br/>    email_rules = map(object({<br/>      id       = string<br/>      name     = string<br/>      enabled  = bool<br/>      priority = number<br/>      matchers = list(object({ type = string, field = optional(string), value = optional(string) }))<br/>      actions  = list(object({ type = string, value = optional(list(string)) }))<br/>    }))<br/>    email_catch_all = object({<br/>      enabled = bool<br/>      actions = list(object({ type = string, value = optional(list(string)) }))<br/>    })<br/>    waf_custom = object({<br/>      id = optional(string)<br/>      rules = list(object({<br/>        ref         = string<br/>        description = string<br/>        expression  = string<br/>        action      = string<br/>        enabled     = bool<br/>      }))<br/>    })<br/>  })</pre> | n/a | yes |
| <a name="input_zone_settings_overrides"></a> [zone\_settings\_overrides](#input\_zone\_settings\_overrides) | Per-zone overrides merged over the default zone-setting posture (setting\_id => value). | `any` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_effective_settings"></a> [effective\_settings](#output\_effective\_settings) | Effective zone-setting posture (defaults merged with overrides). Non-identifying. |
| <a name="output_zone_id"></a> [zone\_id](#output\_zone\_id) | Cloudflare zone ID. |
<!-- END_TF_DOCS -->
