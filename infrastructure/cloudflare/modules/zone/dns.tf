# Email-Routing-owned records (MX/SPF/DKIM) are intentionally excluded; see var.zone validation.
resource "cloudflare_dns_record" "this" {
  for_each = nonsensitive(toset(keys(var.zone.dns_records)))

  zone_id  = cloudflare_zone.this.id
  type     = var.zone.dns_records[each.key].type
  name     = var.zone.dns_records[each.key].name
  content  = var.zone.dns_records[each.key].content
  ttl      = var.zone.dns_records[each.key].ttl
  proxied  = var.zone.dns_records[each.key].proxied
  priority = var.zone.dns_records[each.key].priority
  comment  = var.zone.dns_records[each.key].comment
}
