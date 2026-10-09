module "zone" {
  source   = "./modules/zone"
  for_each = local.zone_keys

  account_id = var.cloudflare_account_id
  zone       = local.cf.zones[each.key]
}
