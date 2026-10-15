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

mock_provider "sops" {
  override_data {
    target = data.sops_file.secrets
    values = {
      raw = <<-EOT
        nextdns:
          accounts:
            account_1:
              account_name: "Decoy Account 1"
              api_key: "decoy-api-key-1"
            account_2:
              account_name: "Decoy Account 2"
              api_key: "decoy-api-key-2"
            account_3:
              account_name: "Decoy Account 3"
              api_key: "decoy-api-key-3"
            account_4:
              account_name: "Decoy Account 4"
              api_key: "decoy-api-key-4"
            account_5:
              account_name: "Decoy Account 5"
              api_key: "decoy-api-key-5"
          config:
            accounts:
              account_1:
                profile_id: "dec001"
                profile_name: "decoy-profile-1"
              account_2:
                profile_id: "dec002"
                profile_name: "decoy-profile-2"
              account_3:
                profile_id: "dec003"
                profile_name: "decoy-profile-3"
              account_4:
                profile_id: "dec004"
                profile_name: "decoy-profile-4"
              account_5:
                profile_id: "dec005"
                profile_name: "decoy-profile-5"
                overrides:
                  inherit_shared_rewrites: true
                  excluded_rewrite_names:
                    - "svc-b.example.test"
                  extra_rewrites:
                    - name: "svc-extra.example.test"
                      content: "192.0.2.99"
                  inherit_shared_allowlist: true
                  excluded_allowlist_ids: []
                  extra_allowlist:
                    - id: "allow-extra.example.test"
                      active: true
                  inherit_shared_denylist: true
                  excluded_denylist_ids: []
                  extra_denylist: []
            shared:
              rewrites:
                - name: "svc-a.example.test"
                  content: "192.0.2.10"
                - name: "svc-b.example.test"
                  content: "192.0.2.20"
              allowlist:
                - id: "allow-a.example.test"
                  active: true
              denylist:
                - id: "deny-a.example.test"
                  active: true
      EOT
    }
  }
}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
  enable_prevent_destroy      = false
}

run "baseline_and_override_merging_plan" {
  command = plan

  assert {
    condition     = output.effective_tags["project"] == "homelab" && output.effective_tags["module"] == "dns"
    error_message = "effective_tags must include project = homelab and module = dns."
  }

  assert {
    condition     = length(nonsensitive(local.effective_accounts["account_1"].rewrites)) == 2 && length(nonsensitive(local.effective_accounts["account_2"].rewrites)) == 2 && length(nonsensitive(local.effective_accounts["account_3"].rewrites)) == 2 && length(nonsensitive(local.effective_accounts["account_4"].rewrites)) == 2
    error_message = "Accounts 1..4 must inherit all 2 shared rewrites."
  }

  assert {
    condition     = length(nonsensitive(local.effective_accounts["account_5"].rewrites)) == 2 && contains([for r in nonsensitive(local.effective_accounts["account_5"].rewrites) : r.name], "svc-extra.example.test") && !contains([for r in nonsensitive(local.effective_accounts["account_5"].rewrites) : r.name], "svc-b.example.test")
    error_message = "Account 5 must exclude svc-b.example.test and append svc-extra.example.test."
  }

  assert {
    condition     = length(nonsensitive(local.effective_accounts["account_5"].allowlist)) == 2
    error_message = "Account 5 must merge shared allowlist (1) + extra_allowlist (1) = 2 entries."
  }
}

run "apply_all_five_accounts" {
  command = apply

  assert {
    condition     = nonsensitive(output.profile_ids)["account_1"] == "dec001" && nonsensitive(output.profile_ids)["account_5"] == "dec005"
    error_message = "Applied profile_ids output must map account_1..account_5 to their mocked profile IDs."
  }
}
