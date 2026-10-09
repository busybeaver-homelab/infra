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
      id       = string
      type     = string
      name     = string
      content  = string
      ttl      = number
      proxied  = bool
      priority = optional(number)
      comment  = optional(string)
    }))
    email_rules = map(object({
      id       = string
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
      for r in values(var.zone.dns_records) :
      !(r.type == "MX" && endswith(lower(r.content), ".mx.cloudflare.net"))
    ])
    error_message = "Email Routing MX records are owned by Email Routing and must not be managed as cloudflare_dns_record."
  }
}

variable "zone_settings_overrides" {
  type        = any
  description = "Per-zone overrides merged over the default zone-setting posture (setting_id => value)."
  default     = {}
}
