locals {
  ephemeral_accounts = try(yamldecode(ephemeral.sops_file.secrets.raw).nextdns.accounts, {})
  config             = sensitive(jsondecode(data.external.sops_config.result.json))
  account_ids        = ["account_1", "account_2", "account_3", "account_4", "account_5"]

  # Mandatory repository tagging map (AGENTS.md §2 / STD-OT-35).
  # NextDNS resources do not expose cloud provider tag attributes, so we expose
  # effective_tags as an output for cross-module governance parity.
  effective_tags = {
    project    = "homelab"
    managed_by = "opentofu"
    module     = "dns"
  }

  account_api_keys = {
    for k in local.account_ids :
    k => nonsensitive(try(local.ephemeral_accounts[k].api_key, "mock-api-key"))
  }

  # Non-sensitive baseline posture shared across account_1..account_4, and used
  # as the base for account_5 before applying per-account overrides.
  baseline_posture = {
    security = {
      threat_intelligence_feeds = true
      ai_threat_detection       = true
      google_safe_browsing      = true
      cryptojacking             = true
      dns_rebinding             = true
      idn_homographs            = true
      typosquatting             = true
      dga                       = true
      nrd                       = true
      ddns                      = false
      parking                   = true
      csam                      = true
      tlds                      = []
    }
    privacy = {
      disguised_trackers = true
      allow_affiliate    = false
      blocklists = [
        "nextdns-recommended",
        "adguard-dns-filter",
        "easylist-germany",
        "hagezi-multi-pro",
      ]
      natives = [
        "apple",
        "samsung",
        "sonos",
        "windows",
        "xiaomi",
      ]
    }
    parental_control = {
      safe_search             = false
      youtube_restricted_mode = false
      block_bypass            = false
      categories              = []
      services = [
        {
          id         = "vk"
          active     = true
          recreation = false
        },
      ]
    }
    settings = {
      bav  = false
      web3 = false
      logs = {
        enabled     = true
        drop_ip     = true
        drop_domain = false
        retention   = "1 day"
        location    = "ch"
      }
      block_page = {
        enabled = false
      }
      performance = {
        ecs              = true
        cache_boost      = true
        cname_flattening = true
      }
    }
  }

  shared_rewrites  = try(local.config.shared.rewrites, [])
  shared_allowlist = try(local.config.shared.allowlist, [])
  shared_denylist  = try(local.config.shared.denylist, [])

  effective_accounts = {
    for k in local.account_ids : k => {
      account_name = try(local.config.accounts[k].account_name, local.config.accounts[k].profile_name)
      profile_id   = local.config.accounts[k].profile_id
      profile_name = local.config.accounts[k].profile_name

      security         = merge(local.baseline_posture.security, try(local.config.accounts[k].overrides.security, {}))
      privacy          = try(local.config.accounts[k].overrides.privacy, local.baseline_posture.privacy)
      parental_control = try(local.config.accounts[k].overrides.parental_control, local.baseline_posture.parental_control)
      settings         = try(local.config.accounts[k].overrides.settings, local.baseline_posture.settings)

      rewrites = concat(
        [
          for r in(try(local.config.accounts[k].overrides.inherit_shared_rewrites, true) ? local.shared_rewrites : []) :
          r if !contains(try(local.config.accounts[k].overrides.excluded_rewrite_names, []), r.name)
        ],
        try(local.config.accounts[k].overrides.extra_rewrites, [])
      )

      allowlist = concat(
        [
          for d in(try(local.config.accounts[k].overrides.inherit_shared_allowlist, true) ? local.shared_allowlist : []) :
          d if !contains(try(local.config.accounts[k].overrides.excluded_allowlist_ids, []), d.id)
        ],
        try(local.config.accounts[k].overrides.extra_allowlist, [])
      )

      denylist = concat(
        [
          for d in(try(local.config.accounts[k].overrides.inherit_shared_denylist, true) ? local.shared_denylist : []) :
          d if !contains(try(local.config.accounts[k].overrides.excluded_denylist_ids, []), d.id)
        ],
        try(local.config.accounts[k].overrides.extra_denylist, [])
      )
    }
  }
}
