mock_provider "nextdns" {
  alias = "account_1"
  mock_resource "nextdns_profile" { defaults = { id = "dec001" } }
}
mock_provider "nextdns" {
  alias = "account_2"
  mock_resource "nextdns_profile" { defaults = { id = "dec002" } }
}
mock_provider "nextdns" {
  alias = "account_3"
  mock_resource "nextdns_profile" { defaults = { id = "dec003" } }
}
mock_provider "nextdns" {
  alias = "account_4"
  mock_resource "nextdns_profile" { defaults = { id = "dec004" } }
}
mock_provider "nextdns" {
  alias = "account_5"
  mock_resource "nextdns_profile" { defaults = { id = "dec005" } }
}

mock_provider "sops" {}

mock_provider "external" {
  alias = "initial"
  override_data {
    target = data.external.sops_config
    values = {
      result = {
        json = <<-EOT
          {
            "accounts": {
              "account_1": { "profile_id": "dec001", "profile_name": "p1" },
              "account_2": { "profile_id": "dec002", "profile_name": "p2" },
              "account_3": { "profile_id": "dec003", "profile_name": "p3" },
              "account_4": { "profile_id": "dec004", "profile_name": "p4" },
              "account_5": {
                "profile_id": "dec005",
                "profile_name": "p5",
                "overrides": {
                  "inherit_shared_rewrites": true,
                  "excluded_rewrite_names": [],
                  "extra_rewrites": [],
                  "inherit_shared_allowlist": true,
                  "excluded_allowlist_ids": [],
                  "extra_allowlist": [],
                  "inherit_shared_denylist": true,
                  "excluded_denylist_ids": [],
                  "extra_denylist": []
                }
              }
            },
            "shared": {
              "rewrites": [
                {
                  "name": "svc-a.example.test",
                  "content": "192.0.2.10"
                }
              ],
              "allowlist": [],
              "denylist": []
            }
          }
        EOT
      }
    }
  }
}

mock_provider "external" {
  alias = "mutated"
  override_data {
    target = data.external.sops_config
    values = {
      result = {
        json = <<-EOT
          {
            "accounts": {
              "account_1": { "profile_id": "dec001", "profile_name": "p1" },
              "account_2": { "profile_id": "dec002", "profile_name": "p2" },
              "account_3": { "profile_id": "dec003", "profile_name": "p3" },
              "account_4": { "profile_id": "dec004", "profile_name": "p4" },
              "account_5": {
                "profile_id": "dec005",
                "profile_name": "p5",
                "overrides": {
                  "inherit_shared_rewrites": false,
                  "excluded_rewrite_names": [],
                  "extra_rewrites": [
                    {
                      "name": "only-5.example.test",
                      "content": "192.0.2.55"
                    }
                  ],
                  "inherit_shared_allowlist": true,
                  "excluded_allowlist_ids": [],
                  "extra_allowlist": [],
                  "inherit_shared_denylist": true,
                  "excluded_denylist_ids": [],
                  "extra_denylist": []
                }
              }
            },
            "shared": {
              "rewrites": [
                {
                  "name": "svc-a.example.test",
                  "content": "192.0.2.10"
                }
              ],
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

run "initial_apply" {
  command = apply
  providers = {
    sops              = sops
    external          = external.initial
    nextdns.account_1 = nextdns.account_1
    nextdns.account_2 = nextdns.account_2
    nextdns.account_3 = nextdns.account_3
    nextdns.account_4 = nextdns.account_4
    nextdns.account_5 = nextdns.account_5
  }
}

run "mutate_account_5_override_without_affecting_accounts_1_to_4" {
  command = plan
  providers = {
    sops              = sops
    external          = external.mutated
    nextdns.account_1 = nextdns.account_1
    nextdns.account_2 = nextdns.account_2
    nextdns.account_3 = nextdns.account_3
    nextdns.account_4 = nextdns.account_4
    nextdns.account_5 = nextdns.account_5
  }

  assert {
    condition     = length(nonsensitive(local.effective_accounts["account_1"].rewrites)) == 1 && nonsensitive(local.effective_accounts["account_1"].rewrites)[0].name == "svc-a.example.test"
    error_message = "Account 1 rewrites must remain untouched when Account 5 overrides change."
  }

  assert {
    condition     = length(nonsensitive(local.effective_accounts["account_5"].rewrites)) == 1 && nonsensitive(local.effective_accounts["account_5"].rewrites)[0].name == "only-5.example.test"
    error_message = "Account 5 with inherit_shared_rewrites = false must only contain extra_rewrites."
  }
}
