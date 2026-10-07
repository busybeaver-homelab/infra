resource "cloudflare_record" "root_record" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  content = "192.0.2.1" # Decoy dummy IP
  type    = "A"
  ttl     = 3600
  proxied = true
}
