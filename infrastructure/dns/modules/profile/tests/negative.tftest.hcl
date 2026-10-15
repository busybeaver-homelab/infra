mock_provider "nextdns" {}

variables {
  profile_name = "decoy-profile-1"

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
}

run "reject_empty_profile_name" {
  command = plan

  variables {
    profile_name = "   "
  }

  expect_failures = [
    var.profile_name,
  ]
}

run "reject_empty_security_tld" {
  command = plan

  variables {
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
      tlds                      = [""]
    }
  }

  expect_failures = [
    var.security,
  ]
}

run "reject_empty_privacy_blocklist" {
  command = plan

  variables {
    privacy = {
      disguised_trackers = true
      allow_affiliate    = false
      blocklists         = [""]
      natives            = []
    }
  }

  expect_failures = [
    var.privacy,
  ]
}

run "reject_empty_parental_control_service_id" {
  command = plan

  variables {
    parental_control = {
      safe_search             = false
      youtube_restricted_mode = false
      block_bypass            = false
      categories              = []
      services = [
        {
          id         = " "
          active     = true
          recreation = false
        }
      ]
    }
  }

  expect_failures = [
    var.parental_control,
  ]
}

run "reject_invalid_logs_retention" {
  command = plan

  variables {
    settings = {
      bav  = true
      web3 = false
      logs = {
        enabled     = true
        drop_ip     = false
        drop_domain = false
        retention   = "999d"
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

  expect_failures = [
    var.settings,
  ]
}

run "reject_invalid_logs_location" {
  command = plan

  variables {
    settings = {
      bav  = true
      web3 = false
      logs = {
        enabled     = true
        drop_ip     = false
        drop_domain = false
        retention   = "3 months"
        location    = "SWITZERLAND"
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

  expect_failures = [
    var.settings,
  ]
}

run "reject_empty_rewrite_content" {
  command = plan

  variables {
    rewrites = [
      {
        name    = "svc.example.test"
        content = ""
      }
    ]
  }

  expect_failures = [
    var.rewrites,
  ]
}

run "reject_empty_allowlist_domain" {
  command = plan

  variables {
    allowlist = [
      {
        id     = " "
        active = true
      }
    ]
  }

  expect_failures = [
    var.allowlist,
  ]
}

run "reject_empty_denylist_domain" {
  command = plan

  variables {
    denylist = [
      {
        id     = ""
        active = true
      }
    ]
  }

  expect_failures = [
    var.denylist,
  ]
}
