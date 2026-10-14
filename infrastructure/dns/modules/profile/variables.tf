variable "profile_name" {
  type        = string
  description = "Display name of the NextDNS profile (sensitive per AGENTS.md)."
  sensitive   = true

  validation {
    condition     = length(trimspace(var.profile_name)) > 0
    error_message = "profile_name must be a non-empty string."
  }
}

variable "enable_prevent_destroy" {
  type        = bool
  description = "Whether to enforce prevent_destroy on nextdns_profile.this (STD-OT-44)."
  default     = true
}

variable "security" {
  type = object({
    threat_intelligence_feeds = bool
    ai_threat_detection       = bool
    google_safe_browsing      = bool
    cryptojacking             = bool
    dns_rebinding             = bool
    idn_homographs            = bool
    typosquatting             = bool
    dga                       = bool
    nrd                       = bool
    ddns                      = bool
    parking                   = bool
    csam                      = bool
    tlds                      = list(string)
  })
  description = "Security threat protection settings and blocked TLDs for the NextDNS profile."

  validation {
    condition     = alltrue([for tld in var.security.tlds : length(trimspace(tld)) > 0])
    error_message = "Every entry in security.tlds must be a non-empty TLD identifier."
  }
}

variable "privacy" {
  type = object({
    disguised_trackers = bool
    allow_affiliate    = bool
    blocklists         = list(string)
    natives            = list(string)
  })
  description = "Privacy blocklists, native tracker lists, and CNAME/affiliate flags for the NextDNS profile."

  validation {
    condition     = alltrue([for id in var.privacy.blocklists : length(trimspace(id)) > 0])
    error_message = "Every entry in privacy.blocklists must be a non-empty blocklist identifier."
  }

  validation {
    condition     = alltrue([for id in var.privacy.natives : length(trimspace(id)) > 0])
    error_message = "Every entry in privacy.natives must be a non-empty native tracker list identifier."
  }
}

variable "parental_control" {
  type = object({
    safe_search             = bool
    youtube_restricted_mode = bool
    block_bypass            = bool
    categories = list(object({
      id         = string
      active     = bool
      recreation = bool
    }))
    services = list(object({
      id         = string
      active     = bool
      recreation = bool
    }))
  })
  description = "Parental control settings, blocked categories, and blocked services for the NextDNS profile."

  validation {
    condition = (
      alltrue([for c in var.parental_control.categories : length(trimspace(c.id)) > 0]) &&
      alltrue([for s in var.parental_control.services : length(trimspace(s.id)) > 0])
    )
    error_message = "Every category and service entry in parental_control must have a non-empty id."
  }
}

variable "settings" {
  type = object({
    bav  = bool
    web3 = bool
    logs = object({
      enabled     = bool
      drop_ip     = bool
      drop_domain = bool
      retention   = string
      location    = string
    })
    block_page = object({
      enabled = bool
    })
    performance = object({
      ecs              = bool
      cache_boost      = bool
      cname_flattening = bool
    })
  })
  description = "Operational settings (logs, block_page, performance, bav, web3) for the NextDNS profile."

  validation {
    condition     = contains(["1 hour", "6 hours", "1 day", "1 week", "1 month", "3 months", "6 months", "1 year", "2 years"], var.settings.logs.retention)
    error_message = "settings.logs.retention must be one of the NextDNS provider retention strings: 1 hour, 6 hours, 1 day, 1 week, 1 month, 3 months, 6 months, 1 year, 2 years."
  }

  validation {
    condition     = can(regex("^[a-z]{2}$", var.settings.logs.location))
    error_message = "settings.logs.location must be a 2-letter lowercase ISO country/jurisdiction code (e.g. ch, eu, us)."
  }
}

variable "rewrites" {
  type = list(object({
    name    = string
    content = string
  }))
  description = "Sensitive DNS rewrites (domain -> IP/target) for the NextDNS profile."
  sensitive   = true
  default     = []

  validation {
    condition     = alltrue([for r in var.rewrites : length(trimspace(r.name)) > 0 && length(trimspace(r.content)) > 0])
    error_message = "Every DNS rewrite must have non-empty name and content fields."
  }
}

variable "allowlist" {
  type = list(object({
    id     = string
    active = bool
  }))
  description = "Sensitive allowlist domain entries for the NextDNS profile."
  sensitive   = true
  default     = []

  validation {
    condition     = alltrue([for d in var.allowlist : length(trimspace(d.id)) > 0])
    error_message = "Every allowlist entry must have a non-empty domain id."
  }
}

variable "denylist" {
  type = list(object({
    id     = string
    active = bool
  }))
  description = "Sensitive denylist domain entries for the NextDNS profile."
  sensitive   = true
  default     = []

  validation {
    condition     = alltrue([for d in var.denylist : length(trimspace(d.id)) > 0])
    error_message = "Every denylist entry must have a non-empty domain id."
  }
}
