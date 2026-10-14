mock_provider "nextdns" {
  mock_resource "nextdns_profile" {
    defaults = {
      id = "dec001"
    }
  }
}

variables {
  profile_name           = "decoy-profile-1"
  enable_prevent_destroy = false

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
    tlds                      = ["zip", "mov"]
  }

  privacy = {
    disguised_trackers = true
    allow_affiliate    = false
    blocklists         = ["nextdns-recommended", "oisd"]
    natives            = ["apple", "windows"]
  }

  parental_control = {
    safe_search             = false
    youtube_restricted_mode = false
    block_bypass            = false
    categories = [
      {
        id         = "porn"
        active     = true
        recreation = false
      }
    ]
    services = [
      {
        id         = "tiktok"
        active     = true
        recreation = false
      }
    ]
  }

  settings = {
    bav  = true
    web3 = false
    logs = {
      enabled     = true
      drop_ip     = false
      drop_domain = false
      retention   = "3 months"
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

  rewrites = [
    {
      name    = "svc-a.example.test"
      content = "192.0.2.10"
    }
  ]

  allowlist = [
    {
      id     = "allow-a.example.test"
      active = true
    }
  ]

  denylist = [
    {
      id     = "deny-a.example.test"
      active = true
    }
  ]
}

run "populated_profile_plan_and_invariants" {
  command = plan

  assert {
    condition     = nextdns_security.this.dns_rebinding == true && nextdns_security.this.csam == true
    error_message = "Security baseline flags (dns_rebinding, csam) must be propagated to nextdns_security.this."
  }

  assert {
    condition     = contains(nextdns_privacy.this.blocklists, "nextdns-recommended")
    error_message = "Blocklists must be propagated to nextdns_privacy.this."
  }

  assert {
    condition     = nextdns_settings.this.logs[0].location == "ch" && nextdns_settings.this.logs[0].retention == "3 months"
    error_message = "Log location and retention must match settings.logs."
  }

  assert {
    condition     = output.rewrite_enabled == true && output.allowlist_enabled == true && output.denylist_enabled == true
    error_message = "Non-empty rewrites, allowlist, and denylist must instantiate their corresponding resources."
  }
}

run "empty_lists_suppress_optional_resources" {
  command = plan

  variables {
    rewrites  = []
    allowlist = []
    denylist  = []
  }

  assert {
    condition     = output.rewrite_enabled == false && output.allowlist_enabled == false && output.denylist_enabled == false
    error_message = "Empty rewrites, allowlist, and denylist must set count = 0 on their corresponding resources."
  }
}

run "apply_profile_with_mock_provider" {
  command = apply

  assert {
    condition     = nonsensitive(output.profile_id) == "dec001"
    error_message = "Applied profile_id output must equal the mocked 6-char profile ID."
  }
}
