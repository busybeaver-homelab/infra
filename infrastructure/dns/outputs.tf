output "profile_ids" {
  description = "Map of generic account keys (account_1..account_4) to managed NextDNS profile IDs."
  value = {
    account_1 = module.account_1.profile_id
    account_2 = module.account_2.profile_id
    account_3 = module.account_3.profile_id
    account_4 = module.account_4.profile_id
  }
  sensitive = true
}

output "account_names" {
  description = "Map of generic account keys (account_1..account_4) to encrypted human-readable account labels."
  value = {
    for k, v in local.effective_accounts : k => v.account_name
  }
  sensitive = true
}

output "effective_tags" {
  description = "Mandatory homelab governance tags associated with the dns root module."
  value       = local.effective_tags
}
