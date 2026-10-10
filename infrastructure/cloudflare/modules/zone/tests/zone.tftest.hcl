mock_provider "cloudflare" {
  mock_resource "cloudflare_zone" {
    defaults = {
      id = "0000000000000000000000000000000d"
    }
  }
}

variables {
  account_id             = "test-mock-account-id"
  enable_prevent_destroy = false
  zone = {
    name = "example.com"
    id   = "test-mock-zone-id"
    dns_records = {
      apex = {
        name    = "example.com"
        type    = "A"
        content = "192.0.2.1"
        ttl     = 3600
        proxied = true
      }
    }
    email_rules = {}
    email_catch_all = {
      enabled = false
      actions = []
    }
    waf_custom = {
      rules = [
        {
          ref         = "block_bad_bots"
          description = "Block bad bots"
          expression  = "(cf.client.bot)"
          action      = "block"
          enabled     = true
        }
      ]
    }
  }
}

run "verify_zone_module_plan" {
  command = plan

  assert {
    condition     = cloudflare_zone.this.name == "example.com"
    error_message = "Zone name must match the input parameter"
  }

  assert {
    condition     = cloudflare_zone_dnssec.this.status == "active"
    error_message = "DNSSEC must default to active"
  }
}

run "verify_zone_module_apply" {
  command = apply

  assert {
    condition     = output.zone_id != ""
    error_message = "Zone ID output must not be empty on apply"
  }

  assert {
    condition     = output.effective_settings.ssl == "strict"
    error_message = "Default zone settings must enforce strict SSL"
  }
}
