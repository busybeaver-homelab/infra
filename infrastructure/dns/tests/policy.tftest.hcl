mock_provider "nextdns" {
  alias = "account_1"
  mock_resource "nextdns_profile" {
    defaults = { id = "dec001" }
  }
}

mock_provider "nextdns" {
  alias = "account_2"
  mock_resource "nextdns_profile" {
    defaults = { id = "dec002" }
  }
}

mock_provider "nextdns" {
  alias = "account_3"
  mock_resource "nextdns_profile" {
    defaults = { id = "dec003" }
  }
}

mock_provider "nextdns" {
  alias = "account_4"
  mock_resource "nextdns_profile" {
    defaults = { id = "dec004" }
  }
}

mock_provider "nextdns" {
  alias = "account_5"
  mock_resource "nextdns_profile" {
    defaults = { id = "dec005" }
  }
}

mock_provider "sops" {}

mock_provider "external" {
  override_data {
    target = data.external.sops_config
    values = {
      result = {
        json = <<-EOT
          {
            "accounts": {
              "account_1": {
                "profile_id": "dec001",
                "profile_name": "decoy-profile-1"
              },
              "account_2": {
                "profile_id": "dec002",
                "profile_name": "decoy-profile-2"
              },
              "account_3": {
                "profile_id": "dec003",
                "profile_name": "decoy-profile-3"
              },
              "account_4": {
                "profile_id": "dec004",
                "profile_name": "decoy-profile-4"
              },
              "account_5": {
                "profile_id": "dec005",
                "profile_name": "decoy-profile-5"
              }
            },
            "shared": {
              "rewrites": [],
              "allowlist": [],
              "denylist": []
            }
          }
        EOT
      }
    }
  }
}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
  enable_prevent_destroy      = false
}

# STD-OT-59: Privacy, Swiss log jurisdiction, IP dropping, and tagging invariants for infrastructure/dns.
run "policy_invariants" {
  command = plan

  assert {
    condition = alltrue([
      for acct in values(nonsensitive(local.effective_accounts)) :
      acct.settings.logs.location == "ch" &&
      acct.settings.logs.drop_ip == true &&
      acct.settings.logs.retention == "1 day" &&
      acct.security.ai_threat_detection == true &&
      acct.security.csam == true &&
      acct.security.google_safe_browsing == true &&
      acct.security.threat_intelligence_feeds == true
    ])
    error_message = "Every NextDNS account must enforce Swiss log residency (ch), client IP dropping, 1-day retention, and core threat protection (STD-OT-50, STD-OT-59)."
  }

  assert {
    condition     = output.effective_tags["project"] == "homelab"
    error_message = "DNS effective_tags must enforce project = \"homelab\" (STD-OT-37, STD-OT-59)."
  }
}
