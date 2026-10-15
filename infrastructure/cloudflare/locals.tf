locals {
  # Sensitive: the decoded cloudflare.config tree (identifying values only).
  cf = sensitive(jsondecode(data.external.sops_config.result.json))

  # Logical zone keys (e.g. "primary") are non-identifying and may drive for_each.
  zone_keys = nonsensitive(toset(keys(local.cf.zones)))

  # "<name>|<sorted scopes joined by +>" is unique across the catalog (names alone are not).
  permission_group_ids = {
    for g in data.cloudflare_account_api_token_permission_groups_list.all.result :
    "${g.name}|${join("+", sort(g.scopes))}" => g.id
  }
}
