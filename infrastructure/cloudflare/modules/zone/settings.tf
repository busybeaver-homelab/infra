locals {
  # Live zone posture as of the 2026-10-09 recon (non-identifying).
  default_zone_settings = {
    "0rtt"                    = "off"
    always_online             = "on"
    always_use_https          = "on"
    automatic_https_rewrites  = "on"
    brotli                    = "on"
    browser_cache_ttl         = 14400
    browser_check             = "on"
    cache_level               = "aggressive"
    challenge_ttl             = 1800
    ciphers                   = []
    cname_flattening          = "flatten_at_root"
    development_mode          = "off"
    early_hints               = "on"
    ech                       = "on"
    edge_cache_ttl            = 7200
    email_obfuscation         = "on"
    filter_logs_to_cloudflare = "off"
    hotlink_protection        = "on"
    http3                     = "on"
    ip_geolocation            = "on"
    ipv6                      = "on"
    log_to_cloudflare         = "on"
    max_upload                = 100
    min_tls_version           = "1.3"
    minify                    = { css = "off", html = "off", js = "off" }
    mobile_redirect           = { status = "off", mobile_subdomain = null, strip_uri = false }
    opportunistic_encryption  = "on"
    opportunistic_onion       = "on"
    orange_to_orange          = "off"
    pq_keyex                  = "on"
    privacy_pass              = "on"
    pseudo_ipv4               = "off"
    replace_insecure_js       = "on"
    rocket_loader             = "off"
    security_header = {
      strict_transport_security = {
        enabled            = true
        max_age            = 15552000
        include_subdomains = true
        preload            = true
        nosniff            = true
      }
    }
    security_level      = "medium"
    server_side_exclude = "on"
    ssl                 = "strict"
    tls_1_2_only        = "off"
    tls_1_3             = "on"
    tls_client_auth     = "on" # Authenticated Origin Pulls (zone-level)
    visitor_ip          = "on"
    waf                 = "off"
    websockets          = "off"
  }

  zone_settings = merge(local.default_zone_settings, var.zone_settings_overrides)
}

resource "cloudflare_zone_setting" "this" {
  for_each = toset(keys(local.zone_settings))

  zone_id    = cloudflare_zone.this.id
  setting_id = each.key
  value      = local.zone_settings[each.key]
}
