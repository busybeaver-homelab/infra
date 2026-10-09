resource "cloudflare_email_routing_settings" "this" {
  zone_id            = cloudflare_zone.this.id
  support_subaddress = false
}

resource "cloudflare_email_routing_rule" "this" {
  for_each = nonsensitive(toset(keys(var.zone.email_rules)))

  zone_id  = cloudflare_zone.this.id
  name     = var.zone.email_rules[each.key].name
  enabled  = var.zone.email_rules[each.key].enabled
  priority = var.zone.email_rules[each.key].priority
  matchers = var.zone.email_rules[each.key].matchers
  actions  = var.zone.email_rules[each.key].actions
}

resource "cloudflare_email_routing_catch_all" "this" {
  zone_id  = cloudflare_zone.this.id
  name     = "" # live catch-all carries an empty name
  enabled  = var.zone.email_catch_all.enabled
  matchers = [{ type = "all" }]
  actions  = var.zone.email_catch_all.actions
}
