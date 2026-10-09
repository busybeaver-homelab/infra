resource "cloudflare_email_routing_address" "this" {
  for_each = nonsensitive(toset(keys(local.cf.email_destinations)))

  account_id = var.cloudflare_account_id
  email      = local.cf.email_destinations[each.key].email
}
