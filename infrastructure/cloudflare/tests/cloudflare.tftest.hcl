mock_provider "cloudflare" {
  # Rulesets validate zone_id as 32-hex; pin a zero-padded decoy instead of the mock's random string.
  mock_resource "cloudflare_zone" {
    defaults = {
      id = "0000000000000000000000000000000d"
    }
  }
}

mock_provider "sops" {
  override_data {
    target = data.sops_file.secrets
    values = {
      raw = <<-EOT
        cloudflare:
          config:
            account_name: "Decoy Account"
            notification_email: "user@example.test"
            notification_policy_ids:
              expiring_service_token_alert: "00000000000000000000000000000001"
              fbm_volumetric_attack: "00000000000000000000000000000002"
              real_origin_monitoring: "00000000000000000000000000000003"
              bgp_hijack_notification: "00000000000000000000000000000004"
              universal_ssl_event_type: "00000000000000000000000000000005"
            email_destinations:
              dest_1: { id: "00000000000000000000000000000006", email: "user@example.test" }
            zero_trust:
              organization:
                name: "decoy"
                auth_domain: "decoy.cloudflareaccess.com"
                login_design: { background_color: "#000000", header_text: "decoy" }
              otp_idp_id: "00000000000000000000000000000007"
              dns_location: { id: "00000000000000000000000000000008", name: "decoy" }
              split_tunnel_excludes:
                - { address: "198.51.100.0/24", description: "decoy" }
                - { host: "decoy.example.test", description: "decoy" }
            iam:
              tokens:
                r2_state:  { id: "0000000000000000000000000000000a", policies: [{ effect: "allow", resources: "{\"com.cloudflare.edge.r2.bucket.0_default_x\":\"*\"}", permission_groups: ["Decoy Read|com.cloudflare.api.account"] }] }
                terraform: { id: "0000000000000000000000000000000b", policies: [{ effect: "allow", resources: "{\"com.cloudflare.api.account.zone.0\":\"*\"}", permission_groups: ["Decoy Read|com.cloudflare.api.account"] }, { effect: "allow", resources: "{\"com.cloudflare.api.account.0\":\"*\"}", permission_groups: ["Decoy Read|com.cloudflare.api.account"] }] }
              member: { id: "0000000000000000000000000000000c", email: "user@example.test", resource_group_id: "00000000000000000000000000000012" }
            zones:
              primary:
                name: "example.test"
                id: "0000000000000000000000000000000d"
                dns_records:
                  a_1: { id: "0000000000000000000000000000000e", type: "A", name: "example.test", content: "192.0.2.10", ttl: 1, proxied: false, priority: null, comment: null }
                  txt_1: { id: "0000000000000000000000000000000f", type: "TXT", name: "example.test", content: "\"decoy-txt\"", ttl: 1, proxied: false, priority: null, comment: null }
                email_rules:
                  rule_01: { id: "00000000000000000000000000000010", name: "decoy", enabled: true, priority: 0, matchers: [{ type: "literal", field: "to", value: "a@example.test" }], actions: [{ type: "forward", value: ["user@example.test"] }] }
                email_catch_all: { enabled: false, actions: [{ type: "drop", value: null }] }
                waf_custom:
                  id: "00000000000000000000000000000011"
                  rules:
                    - { ref: "r1", description: "decoy", expression: "(http.host eq \"example.test\")", action: "block", enabled: true }
      EOT
    }
  }
}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
  cloudflare_api_token        = "mock-cf-token-12345"
  cloudflare_account_id       = "mock-account-id-12345"
}

run "verify_r2_state_bucket" {
  command = plan

  assert {
    condition     = cloudflare_r2_bucket.tfstate.name == "homelab-infra-tfstate"
    error_message = "OpenTofu state R2 bucket must be named homelab-infra-tfstate"
  }

  assert {
    condition     = cloudflare_r2_bucket.tfstate.location == "weur"
    error_message = "OpenTofu state R2 bucket location must be weur"
  }

  assert {
    condition     = cloudflare_r2_bucket.tfstate.jurisdiction == "default"
    error_message = "OpenTofu state R2 bucket must stay in the default jurisdiction"
  }
}

run "verify_r2_backup_bucket" {
  command = plan

  assert {
    condition     = cloudflare_r2_bucket.backups_dr.name == "homelab-backups-dr"
    error_message = "R2 disaster recovery backup bucket must be named homelab-backups-dr"
  }

  assert {
    condition     = cloudflare_r2_bucket.backups_dr.location == "weur"
    error_message = "R2 disaster recovery backup bucket location hint must be weur for EU data residency"
  }
}

run "verify_config_plumbing" {
  command = plan

  assert {
    condition     = output.managed_zone_keys == toset(["primary"])
    error_message = "Exactly the 'primary' logical zone must be configured from SOPS"
  }
}

run "verify_zone_module_wiring" {
  command = plan

  assert {
    condition     = toset(keys(module.zone)) == toset(["primary"])
    error_message = "module.zone must be instantiated once per logical zone key"
  }
}

run "verify_account_posture" {
  command = plan

  assert {
    condition     = cloudflare_account.this.settings.enforce_twofactor == true
    error_message = "Account must enforce 2FA"
  }
}

run "verify_zero_trust_baseline" {
  command = plan

  assert {
    condition     = cloudflare_zero_trust_access_identity_provider.otp.type == "onetimepin"
    error_message = "One-time PIN identity provider must be managed"
  }
  assert {
    condition = (cloudflare_zero_trust_gateway_settings.this.settings.antivirus.fail_closed == true &&
    cloudflare_zero_trust_gateway_settings.this.settings.tls_decrypt.enabled == false)
    error_message = "Gateway antivirus must fail closed; TLS decryption must stay off"
  }
  assert {
    condition     = cloudflare_zero_trust_dns_location.default.client_default == true
    error_message = "The default Gateway DNS location must be managed"
  }
  assert {
    condition     = cloudflare_zero_trust_device_default_profile.this.allowed_to_leave == true && cloudflare_zero_trust_device_default_profile.this.switch_locked == false
    error_message = "Default device profile posture mismatch"
  }
}

run "verify_notifications" {
  command = plan

  assert {
    condition = toset(keys(cloudflare_notification_policy.this)) == toset([
      "expiring_service_token_alert", "fbm_volumetric_attack", "real_origin_monitoring",
      "bgp_hijack_notification", "universal_ssl_event_type",
    ])
    error_message = "All five managed alert types must be present (billing_budget_alert is intentionally unmanaged by HCL)"
  }
  assert {
    condition     = alltrue([for p in cloudflare_notification_policy.this : p.enabled])
    error_message = "All managed notification policies must be enabled"
  }
}

run "verify_email_destinations" {
  command = plan

  assert {
    condition     = toset(keys(cloudflare_email_routing_address.this)) == toset(["dest_1"])
    error_message = "One email routing destination per SOPS entry"
  }
}

run "verify_frozen_iam" {
  command = plan

  assert {
    condition     = toset(keys(cloudflare_account_token.frozen)) == toset(["r2_state", "terraform"])
    error_message = "Both remaining account tokens must be documented as frozen resources"
  }
  assert {
    condition     = length(cloudflare_account_token.frozen["terraform"].policies) == 2
    error_message = "The terraform token must document both of its least-privilege policies (account + zone)"
  }
}

run "verify_split_tunnel_host_entries" {
  command = plan

  assert {
    condition = (anytrue([for e in cloudflare_zero_trust_device_default_profile.this.exclude : e.address == "198.51.100.0/24"]) &&
    anytrue([for e in cloudflare_zero_trust_device_default_profile.this.exclude : e.host == "decoy.example.test"]))
    error_message = "Split-tunnel excludes must support both address and host entries"
  }
}

run "frozen_token_missing_blocks_recreation" {
  command = plan

  override_data {
    target = data.cloudflare_account_tokens.all
    values = {
      result = [{ name = "Grafana: Read analytics, logs and radar", condition = null, creator_email_at_creation = null, expires_on = null, id = null, issued_on = null, last_used_on = null, modified_on = null, not_before = null, policies = null, provisioner_id = null, provisioner_type = null, status = null }, { name = "homelab-infra-opentofu-state-r2-token", condition = null, creator_email_at_creation = null, expires_on = null, id = null, issued_on = null, last_used_on = null, modified_on = null, not_before = null, policies = null, provisioner_id = null, provisioner_type = null, status = null }]
    }
  }

  expect_failures = [cloudflare_account_token.frozen]
}

run "frozen_tokens_present_pass" {
  command = plan

  override_data {
    target = data.cloudflare_account_tokens.all
    values = {
      result = [{ name = "homelab-infra-opentofu-state-r2-token", condition = null, creator_email_at_creation = null, expires_on = null, id = null, issued_on = null, last_used_on = null, modified_on = null, not_before = null, policies = null, provisioner_id = null, provisioner_type = null, status = null }, { name = "terraform-homelab-manually-provisioned", condition = null, creator_email_at_creation = null, expires_on = null, id = null, issued_on = null, last_used_on = null, modified_on = null, not_before = null, policies = null, provisioner_id = null, provisioner_type = null, status = null }]
    }
  }

  assert {
    condition     = length(cloudflare_account_token.frozen) == 2
    error_message = "All frozen tokens must plan when they exist live"
  }
}

run "frozen_iam_check_detects_unresolvable_permission" {
  command = plan

  override_data {
    target = data.cloudflare_account_api_token_permission_groups_list.all
    values = {
      result = [{ id = "00000000000000000000000000000013", name = "Unrelated Read", scopes = ["com.cloudflare.api.account"], category = null, is_selectable = null }]
    }
  }

  expect_failures = [check.frozen_iam_references_resolve]
}

run "frozen_iam_check_passes_with_resolvable_catalog" {
  command = plan

  override_data {
    target = data.cloudflare_account_api_token_permission_groups_list.all
    values = {
      result = [{ id = "00000000000000000000000000000013", name = "Decoy Read", scopes = ["com.cloudflare.api.account"], category = null, is_selectable = null }]
    }
  }

  assert {
    condition     = cloudflare_account_token.frozen["terraform"].policies[0].permission_groups[0].id == "00000000000000000000000000000013"
    error_message = "Permission names must resolve to catalog IDs via name|scopes"
  }
}

run "verify_computed_outputs_on_apply" {
  command = apply

  variables {
    enable_prevent_destroy = false
  }

  assert {
    condition     = output.r2_tfstate_bucket_name == "homelab-infra-tfstate"
    error_message = "R2 state bucket name must match homelab-infra-tfstate on apply"
  }

  assert {
    condition     = output.r2_backup_bucket_name == "homelab-backups-dr"
    error_message = "R2 backup bucket name must match homelab-backups-dr on apply"
  }

  assert {
    condition     = output.managed_zone_keys == toset(["primary"])
    error_message = "Managed zone keys must match primary on apply"
  }

  assert {
    condition     = contains(keys(output.zone_ids), "primary")
    error_message = "Zone IDs map must contain primary on apply"
  }
}
