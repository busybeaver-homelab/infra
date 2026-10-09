# TRANSIENT: one-off adoption of manually created Cloudflare objects. Delete after the
# import apply succeeds (plan Task 12). IDs come from SOPS and stay sensitive.

locals {
  imp  = var.run_imports
  acct = var.cloudflare_account_id

  # Non-identifying composite keys "<zone_key>.<item_key>" for module-scoped collections.
  imp_dns = local.imp ? nonsensitive(toset(flatten([
    for zk, z in local.cf.zones : [for rk in keys(z.dns_records) : "${zk}.${rk}"]
  ]))) : toset([])
  imp_email = local.imp ? nonsensitive(toset(flatten([
    for zk, z in local.cf.zones : [for rk in keys(z.email_rules) : "${zk}.${rk}"]
  ]))) : toset([])
  imp_zones = local.imp ? local.zone_keys : toset([])
  # Literal copy of modules/zone/settings.tf keys: referencing module.zone outputs here creates a
  # graph cycle. A mismatch surfaces as an extra cloudflare_zone_setting "create" in the plan.
  imp_setting_ids = [
    "0rtt",
    "always_online",
    "always_use_https",
    "automatic_https_rewrites",
    "brotli",
    "browser_cache_ttl",
    "browser_check",
    "cache_level",
    "challenge_ttl",
    "ciphers",
    "cname_flattening",
    "development_mode",
    "early_hints",
    "ech",
    "edge_cache_ttl",
    "email_obfuscation",
    "filter_logs_to_cloudflare",
    "hotlink_protection",
    "http3",
    "ip_geolocation",
    "ipv6",
    "log_to_cloudflare",
    "max_upload",
    "min_tls_version",
    "minify",
    "mobile_redirect",
    "opportunistic_encryption",
    "opportunistic_onion",
    "orange_to_orange",
    "pq_keyex",
    "privacy_pass",
    "pseudo_ipv4",
    "replace_insecure_js",
    "rocket_loader",
    "security_header",
    "security_level",
    "server_side_exclude",
    "ssl",
    "tls_1_2_only",
    "tls_1_3",
    "tls_client_auth",
    "visitor_ip",
    "waf",
    "websockets",
  ]
  imp_waf = local.imp ? toset([for zk in local.zone_keys : zk if nonsensitive(length(local.cf.zones[zk].waf_custom.rules)) > 0]) : toset([])
}

# ---- account scope ----
import {
  for_each = local.imp ? toset(["this"]) : toset([])
  to       = cloudflare_account.this
  id       = nonsensitive(local.acct)
}
import {
  for_each = local.imp ? toset(["this"]) : toset([])
  to       = cloudflare_zero_trust_organization.this
  id       = nonsensitive(local.acct)
}
import {
  for_each = local.imp ? toset(["this"]) : toset([])
  to       = cloudflare_zero_trust_access_identity_provider.otp
  id       = nonsensitive("accounts/${local.acct}/${local.cf.zero_trust.otp_idp_id}")
}
import {
  for_each = local.imp ? toset(["this"]) : toset([])
  to       = cloudflare_zero_trust_gateway_settings.this
  id       = nonsensitive(local.acct)
}
import {
  for_each = local.imp ? toset(["this"]) : toset([])
  to       = cloudflare_zero_trust_dns_location.default
  id       = nonsensitive("${local.acct}/${local.cf.zero_trust.dns_location.id}")
}
import {
  for_each = local.imp ? toset(["this"]) : toset([])
  to       = cloudflare_zero_trust_device_default_profile.this
  id       = nonsensitive(local.acct)
}
import {
  for_each = local.imp ? toset(keys(local.notification_policies)) : toset([])
  to       = cloudflare_notification_policy.this[each.key]
  id       = nonsensitive("${local.acct}/${local.cf.notification_policy_ids[each.key]}")
}
import {
  for_each = local.imp ? nonsensitive(toset(keys(local.cf.email_destinations))) : toset([])
  to       = cloudflare_email_routing_address.this[each.key]
  id       = nonsensitive("${local.acct}/${local.cf.email_destinations[each.key].id}")
}
import {
  for_each = local.imp ? toset(keys(local.frozen_token_names)) : toset([])
  to       = cloudflare_account_token.frozen[each.key]
  id       = nonsensitive("${local.acct}/${local.cf.iam.tokens[each.key].id}")
}
import {
  for_each = local.imp ? toset(["this"]) : toset([])
  to       = cloudflare_account_member.frozen
  id       = nonsensitive("${local.acct}/${local.cf.iam.member.id}")
}

# ---- zone scope (module.zone[<zone_key>]) ----
import {
  for_each = local.imp_zones
  to       = module.zone[each.key].cloudflare_zone.this
  id       = nonsensitive(local.cf.zones[each.key].id)
}
import {
  for_each = local.imp_zones
  to       = module.zone[each.key].cloudflare_zone_dnssec.this
  id       = nonsensitive(local.cf.zones[each.key].id)
}
import {
  for_each = toset(flatten([for zk in local.imp_zones : [for s in local.imp_setting_ids : "${zk}.${s}"]]))
  to       = module.zone[split(".", each.key)[0]].cloudflare_zone_setting.this[split(".", each.key)[1]]
  id       = nonsensitive("${local.cf.zones[split(".", each.key)[0]].id}/${split(".", each.key)[1]}")
}
import {
  for_each = local.imp_dns
  to       = module.zone[split(".", each.key)[0]].cloudflare_dns_record.this[split(".", each.key)[1]]
  id       = nonsensitive("${local.cf.zones[split(".", each.key)[0]].id}/${local.cf.zones[split(".", each.key)[0]].dns_records[split(".", each.key)[1]].id}")
}
import {
  for_each = local.imp_zones
  to       = module.zone[each.key].cloudflare_email_routing_settings.this
  id       = nonsensitive(local.cf.zones[each.key].id)
}
import {
  for_each = local.imp_email
  to       = module.zone[split(".", each.key)[0]].cloudflare_email_routing_rule.this[split(".", each.key)[1]]
  id       = nonsensitive("${local.cf.zones[split(".", each.key)[0]].id}/${local.cf.zones[split(".", each.key)[0]].email_rules[split(".", each.key)[1]].id}")
}
import {
  for_each = local.imp_zones
  to       = module.zone[each.key].cloudflare_email_routing_catch_all.this
  id       = nonsensitive(local.cf.zones[each.key].id)
}
import {
  for_each = local.imp_waf
  to       = module.zone[each.key].cloudflare_ruleset.waf_custom[0]
  id       = nonsensitive("zones/${local.cf.zones[each.key].id}/${local.cf.zones[each.key].waf_custom.id}")
}
import {
  for_each = local.imp_zones
  to       = module.zone[each.key].cloudflare_bot_management.this
  id       = nonsensitive(local.cf.zones[each.key].id)
}
