resource "cloudflare_zone" "this" {
  account = { id = var.account_id }
  name    = var.zone.name
  type    = "full"

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = length(setsubtract(keys(var.zone_settings_overrides), keys(local.default_zone_settings))) == 0
      error_message = "zone_settings_overrides contains unknown setting ids; only keys of local.default_zone_settings may be overridden."
    }
  }
}

resource "cloudflare_zone_dnssec" "this" {
  zone_id = cloudflare_zone.this.id
  status  = "active"

  lifecycle {
    prevent_destroy = true
  }
}
