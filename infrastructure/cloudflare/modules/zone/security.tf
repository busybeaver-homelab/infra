# Zone entrypoint ruleset for WAF custom rules. Created only when rules exist.
resource "cloudflare_ruleset" "waf_custom" {
  count = nonsensitive(length(var.zone.waf_custom.rules)) > 0 ? 1 : 0

  zone_id = cloudflare_zone.this.id
  kind    = "zone"
  name    = "default"
  phase   = "http_request_firewall_custom"
  rules   = var.zone.waf_custom.rules
}

resource "cloudflare_bot_management" "this" {
  zone_id               = cloudflare_zone.this.id
  fight_mode            = true # Bot Fight Mode (Free plan)
  enable_js             = true
  is_robots_txt_managed = true
  ai_bots_protection    = "disabled"
  crawler_protection    = "disabled"
}
