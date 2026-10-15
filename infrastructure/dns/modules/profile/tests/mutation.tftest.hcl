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
    tlds                      = []
  }

  privacy = {
    disguised_trackers = true
    allow_affiliate    = false
    blocklists         = ["nextdns-recommended"]
    natives            = []
  }

  parental_control = {
    safe_search             = false
    youtube_restricted_mode = false
    block_bypass            = false
    categories              = []
    services                = []
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
}

run "initial_apply" {
  command = apply
}

run "mutate_security_and_rewrites" {
  command = plan

  variables {
    security = {
      threat_intelligence_feeds = true
      ai_threat_detection       = true
      google_safe_browsing      = true
      cryptojacking             = true
      dns_rebinding             = false
      idn_homographs            = true
      typosquatting             = true
      dga                       = true
      nrd                       = true
      ddns                      = false
      parking                   = true
      csam                      = true
      tlds                      = ["zip"]
    }

    rewrites = [
      {
        name    = "svc-a.example.test"
        content = "192.0.2.10"
      },
      {
        name    = "svc-b.example.test"
        content = "192.0.2.20"
      }
    ]
  }

  assert {
    condition     = nextdns_security.this.dns_rebinding == false && contains(nextdns_security.this.tlds, "zip")
    error_message = "Mutating security.dns_rebinding and security.tlds must update nextdns_security.this in place."
  }

  assert {
    condition     = length(nextdns_rewrite.this[0].rewrite) == 2
    error_message = "Adding a second rewrite entry must update nextdns_rewrite.this[0] to 2 entries."
  }
}
