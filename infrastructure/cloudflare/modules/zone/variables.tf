variable "account_id" {
  type        = string
  description = "Cloudflare account ID owning the zone."
  sensitive   = true
}

variable "zone" {
  type = object({
    name = string
    id   = string
    dns_records = map(object({
      id       = optional(string)
      type     = string
      name     = string
      content  = string
      ttl      = number
      proxied  = bool
      priority = optional(number)
      comment  = optional(string)
    }))
    email_rules = map(object({
      id       = optional(string)
      name     = string
      enabled  = bool
      priority = number
      matchers = list(object({ type = string, field = optional(string), value = optional(string) }))
      actions  = list(object({ type = string, value = optional(list(string)) }))
    }))
    email_catch_all = object({
      enabled = bool
      actions = list(object({ type = string, value = optional(list(string)) }))
    })
    waf_custom = object({
      id = optional(string)
      rules = list(object({
        ref         = string
        description = string
        expression  = string
        action      = string
        enabled     = bool
      }))
    })
  })
  description = "Identifying zone data decoded from SOPS (cloudflare.config.zones.<key>)."
  sensitive   = true

  validation {
    condition = alltrue([
      for r in values(var.zone.dns_records) : !(
        (r.type == "MX" && endswith(trimsuffix(lower(r.content), "."), ".mx.cloudflare.net")) ||
        (r.type == "TXT" && can(regex("^cf[0-9]{4}-[0-9]+\\._domainkey\\.", lower(r.name))))
      )
    ])
    error_message = "Email Routing MX and DKIM records are owned by Email Routing and must not be managed as cloudflare_dns_record."
  }

  # M3: only actions that are valid for the http_request_firewall_custom phase.
  validation {
    condition = alltrue([
      for r in var.zone.waf_custom.rules :
      contains(["block", "challenge", "js_challenge", "managed_challenge", "log", "skip"], r.action)
    ])
    error_message = "waf_custom.rules[*].action must be one of: block, challenge, js_challenge, managed_challenge, log, skip."
  }
}

variable "zone_settings_overrides" {
  type        = any
  description = "Per-zone overrides merged over the default zone-setting posture (setting_id => value)."
  default     = {}
}
