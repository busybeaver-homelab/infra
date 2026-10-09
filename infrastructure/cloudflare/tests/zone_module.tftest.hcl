mock_provider "cloudflare" {
  # Rulesets validate zone_id as 32-hex; pin a zero-padded decoy instead of the mock's random string.
  mock_resource "cloudflare_zone" {
    defaults = {
      id = "0000000000000000000000000000000d"
    }
  }
}

variables {
  account_id = "mock-account"
  zone = {
    name = "example.test"
    id   = "mock-zone"
    dns_records = {
      a_1   = { id = "r1", type = "A", name = "example.test", content = "192.0.2.10", ttl = 1, proxied = false, priority = null, comment = null }
      txt_1 = { id = "r2", type = "TXT", name = "example.test", content = "\"decoy\"", ttl = 1, proxied = false, priority = null, comment = "decoy" }
    }
    email_rules = {
      rule_01 = { id = "e1", name = "decoy", enabled = true, priority = 0, matchers = [{ type = "literal", field = "to", value = "a@example.test" }], actions = [{ type = "forward", value = ["user@example.test"] }] }
    }
    email_catch_all = { enabled = false, actions = [{ type = "drop", value = null }] }
    waf_custom = {
      id    = "w1"
      rules = [{ ref = "r1", description = "decoy", expression = "(http.host eq \"example.test\")", action = "block", enabled = true }]
    }
  }
}

run "security_posture" {
  command = plan
  module { source = "./modules/zone" }

  assert {
    condition     = output.effective_settings["ssl"] == "strict"
    error_message = "SSL mode must be strict"
  }
  assert {
    condition     = output.effective_settings["min_tls_version"] == "1.3"
    error_message = "Minimum TLS version must be 1.3"
  }
  assert {
    condition     = output.effective_settings["always_use_https"] == "on" && output.effective_settings["tls_1_3"] == "on"
    error_message = "Always Use HTTPS and TLS 1.3 must be on"
  }
  assert {
    condition = (output.effective_settings["security_header"].strict_transport_security.enabled &&
    output.effective_settings["security_header"].strict_transport_security.include_subdomains)
    error_message = "HSTS must be enabled including subdomains"
  }
  assert {
    condition     = output.effective_settings["tls_client_auth"] == "on"
    error_message = "Authenticated Origin Pulls (tls_client_auth) must be on"
  }
  assert {
    condition     = cloudflare_bot_management.this.fight_mode == true
    error_message = "Bot Fight Mode must be on"
  }
  assert {
    condition     = length(cloudflare_zone_setting.this) == length(output.effective_settings)
    error_message = "One cloudflare_zone_setting per effective setting"
  }
}

run "zone_and_collections" {
  command = plan
  module { source = "./modules/zone" }

  assert {
    condition     = cloudflare_zone.this.type == "full" && cloudflare_zone_dnssec.this.status == "active"
    error_message = "Zone must be a full setup with DNSSEC active"
  }
  assert {
    condition     = toset(keys(cloudflare_dns_record.this)) == toset(["a_1", "txt_1"])
    error_message = "One DNS record per input key"
  }
  assert {
    condition     = length(cloudflare_email_routing_rule.this) == 1 && cloudflare_email_routing_catch_all.this.enabled == false
    error_message = "Email routing rules and catch-all must mirror input"
  }
  assert {
    condition = (cloudflare_ruleset.waf_custom[0].phase == "http_request_firewall_custom" &&
      cloudflare_ruleset.waf_custom[0].kind == "zone" &&
    length(cloudflare_ruleset.waf_custom[0].rules) == 1)
    error_message = "WAF custom ruleset must be the zone's http_request_firewall_custom entrypoint"
  }
}

run "reject_email_routing_mx" {
  command = plan
  module { source = "./modules/zone" }

  variables {
    zone = {
      name            = "example.test"
      id              = "mock-zone"
      dns_records     = { mx_1 = { id = "m1", type = "MX", name = "example.test", content = "route1.mx.cloudflare.net", ttl = 1, proxied = false, priority = 10, comment = null } }
      email_rules     = {}
      email_catch_all = { enabled = false, actions = [{ type = "drop", value = null }] }
      waf_custom      = { id = "w1", rules = [] }
    }
  }

  expect_failures = [var.zone]
}

run "empty_optional_collections" {
  command = plan
  module { source = "./modules/zone" }

  variables {
    zone = {
      name            = "example.test"
      id              = "mock-zone"
      dns_records     = {}
      email_rules     = {}
      email_catch_all = { enabled = false, actions = [{ type = "drop", value = null }] }
      waf_custom      = { id = null, rules = [] }
    }
  }

  assert {
    condition     = length(cloudflare_dns_record.this) == 0 && length(cloudflare_email_routing_rule.this) == 0 && length(cloudflare_ruleset.waf_custom) == 0
    error_message = "Empty collections must yield zero instances"
  }
}

run "settings_override_wins" {
  command = plan
  module { source = "./modules/zone" }

  variables {
    zone_settings_overrides = { security_level = "high" }
  }

  assert {
    condition     = output.effective_settings["security_level"] == "high" && output.effective_settings["ssl"] == "strict"
    error_message = "Override must win for its key and leave other defaults intact"
  }
}
