resource "nextdns_profile" "this" {
  name = var.profile_name

  lifecycle {
    prevent_destroy = var.enable_prevent_destroy
  }
}

resource "nextdns_security" "this" {
  profile_id                = nextdns_profile.this.id
  threat_intelligence_feeds = var.security.threat_intelligence_feeds
  ai_threat_detection       = var.security.ai_threat_detection
  google_safe_browsing      = var.security.google_safe_browsing
  crypto_jacking            = var.security.cryptojacking
  dns_rebinding             = var.security.dns_rebinding
  idn_homographs            = var.security.idn_homographs
  typo_squatting            = var.security.typosquatting
  dga                       = var.security.dga
  nrd                       = var.security.nrd
  ddns                      = var.security.ddns
  parking                   = var.security.parking
  csam                      = var.security.csam
  tlds                      = var.security.tlds
}

resource "nextdns_privacy" "this" {
  profile_id         = nextdns_profile.this.id
  disguised_trackers = var.privacy.disguised_trackers
  allow_affiliate    = var.privacy.allow_affiliate
  blocklists         = var.privacy.blocklists
  natives            = var.privacy.natives
}

resource "nextdns_parental_control" "this" {
  profile_id              = nextdns_profile.this.id
  safe_search             = var.parental_control.safe_search
  youtube_restricted_mode = var.parental_control.youtube_restricted_mode
  block_bypass            = var.parental_control.block_bypass

  dynamic "category" {
    for_each = var.parental_control.categories
    content {
      id         = category.value.id
      active     = category.value.active
      recreation = category.value.recreation
    }
  }

  dynamic "service" {
    for_each = var.parental_control.services
    content {
      id         = service.value.id
      active     = service.value.active
      recreation = service.value.recreation
    }
  }
}

resource "nextdns_settings" "this" {
  profile_id = nextdns_profile.this.id
  web3       = var.settings.web3

  logs {
    enabled   = var.settings.logs.enabled
    retention = var.settings.logs.retention
    location  = var.settings.logs.location

    privacy {
      log_clients_ip = !var.settings.logs.drop_ip
      log_domains    = !var.settings.logs.drop_domain
    }
  }

  block_page {
    enabled = var.settings.block_page.enabled
  }

  performance {
    ecs              = var.settings.performance.ecs
    cache_boost      = var.settings.performance.cache_boost
    cname_flattening = var.settings.performance.cname_flattening
  }
}

resource "nextdns_rewrite" "this" {
  count      = length(var.rewrites) > 0 ? 1 : 0
  profile_id = nextdns_profile.this.id

  dynamic "rewrite" {
    for_each = var.rewrites
    content {
      domain  = rewrite.value.name
      address = rewrite.value.content
    }
  }
}

resource "nextdns_allowlist" "this" {
  count      = length(var.allowlist) > 0 ? 1 : 0
  profile_id = nextdns_profile.this.id

  dynamic "domain" {
    for_each = var.allowlist
    content {
      id     = domain.value.id
      active = domain.value.active
    }
  }
}

resource "nextdns_denylist" "this" {
  count      = length(var.denylist) > 0 ? 1 : 0
  profile_id = nextdns_profile.this.id

  dynamic "domain" {
    for_each = var.denylist
    content {
      id     = domain.value.id
      active = domain.value.active
    }
  }
}
