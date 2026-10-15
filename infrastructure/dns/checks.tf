check "enforce_nextdns_account_posture" {
  assert {
    condition = alltrue([
      for k in local.account_ids :
      length(trimspace(local.account_api_keys[k])) > 0 &&
      length(trimspace(local.effective_accounts[k].profile_id)) > 0 &&
      length(trimspace(local.effective_accounts[k].profile_name)) > 0
    ])
    error_message = "All five NextDNS accounts (account_1..account_5) must have non-empty api_key, profile_id, and profile_name values in SOPS."
  }

  assert {
    condition = alltrue([
      for k in local.account_ids :
      length(local.effective_accounts[k].privacy.blocklists) > 0
    ])
    error_message = "Every NextDNS account must configure at least one privacy blocklist."
  }
}
