resource "cloudflare_zone" "this" {
  account = { id = var.account_id }
  name    = var.zone.name
  type    = "full"

  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone_dnssec" "this" {
  zone_id = cloudflare_zone.this.id
  status  = "active"

  lifecycle {
    prevent_destroy = true
  }
}
