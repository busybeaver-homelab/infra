resource "tailscale_dns_preferences" "homelab" {
  magic_dns = true
}

resource "tailscale_dns_nameservers" "homelab" {
  count       = length(var.dns_nameservers) > 0 ? 1 : 0
  nameservers = var.dns_nameservers
}




resource "tailscale_dns_search_paths" "homelab" {
  search_paths = var.dns_search_paths
}

resource "tailscale_dns_split_nameservers" "routes" {
  for_each    = var.dns_split_nameservers
  domain      = each.key
  nameservers = each.value
}

