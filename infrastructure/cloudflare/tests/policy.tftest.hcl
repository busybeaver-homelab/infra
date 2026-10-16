mock_provider "cloudflare" {
  mock_resource "cloudflare_zone" {
    defaults = {
      id = "0000000000000000000000000000000d"
    }
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
            "account_name": "Decoy Account",
            "notification_email": "user@example.test",
            "notification_policy_ids": {
              "expiring_service_token_alert": "00000000000000000000000000000001",
              "fbm_volumetric_attack": "00000000000000000000000000000002",
              "real_origin_monitoring": "00000000000000000000000000000003",
              "bgp_hijack_notification": "00000000000000000000000000000004",
              "universal_ssl_event_type": "00000000000000000000000000000005"
            },
            "email_destinations": {
              "dest_1": { "id": "00000000000000000000000000000006", "email": "user@example.test" }
            },
            "zero_trust": {
              "organization": {
                "name": "decoy",
                "auth_domain": "decoy.cloudflareaccess.com",
                "login_design": { "background_color": "#000000", "header_text": "decoy" }
              },
              "otp_idp_id": "00000000000000000000000000000007",
              "dns_location": { "id": "00000000000000000000000000000008", "name": "decoy" },
              "split_tunnel_excludes": [
                { "address": "198.51.100.0/24", "description": "decoy" },
                { "host": "decoy.example.test", "description": "decoy" }
              ]
            },
            "iam": {
              "tokens": {
                "r2_restic_prune": { "id": "0000000000000000000000000000001c", "policies": [{ "effect": "allow", "resources": "{\"com.cloudflare.edge.r2.bucket.0_default_homelab-backups-dr\":\"*\"}", "permission_groups": ["Decoy Read|com.cloudflare.api.account"] }] },
                "r2_state": { "id": "0000000000000000000000000000000a", "policies": [{ "effect": "allow", "resources": "{\"com.cloudflare.edge.r2.bucket.0_default_x\":\"*\"}", "permission_groups": ["Decoy Read|com.cloudflare.api.account"] }] },
                "terraform": { "id": "0000000000000000000000000000000b", "policies": [{ "effect": "allow", "resources": "{\"com.cloudflare.api.account.zone.0\":\"*\"}", "permission_groups": ["Decoy Read|com.cloudflare.api.account"] }, { "effect": "allow", "resources": "{\"com.cloudflare.api.account.0\":\"*\"}", "permission_groups": ["Decoy Read|com.cloudflare.api.account"] }] }
              },
              "member": { "id": "0000000000000000000000000000000c", "email": "user@example.test", "resource_group_id": "00000000000000000000000000000012" }
            },
            "zones": {
              "primary": {
                "name": "example.test",
                "id": "0000000000000000000000000000000d",
                "dns_records": {
                  "a_1": { "id": "0000000000000000000000000000000e", "type": "A", "name": "example.test", "content": "192.0.2.10", "ttl": 1, "proxied": false, "priority": null, "comment": null }
                },
                "email_rules": {
                  "rule_01": { "id": "00000000000000000000000000000010", "name": "decoy", "enabled": true, "priority": 0, "matchers": [{ "type": "literal", "field": "to", "value": "a@example.test" }], "actions": [{ "type": "forward", "value": ["user@example.test"] }] }
                },
                "email_catch_all": { "enabled": false, "actions": [{ "type": "drop", "value": null }] },
                "waf_custom": {
                  "id": "00000000000000000000000000000011",
                  "rules": [
                    { "ref": "r1", "description": "decoy", "expression": "(http.host eq \"example.test\")", "action": "block", "enabled": true }
                  ]
                }
              }
            }
          }
        EOT
      }
    }
  }
}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
  cloudflare_api_token        = "mock-cf-token-12345"
  cloudflare_account_id       = "mock-account-id-12345"
}

# STD-OT-59: Security and Free-Tier policy invariants for infrastructure/cloudflare.
run "policy_invariants" {
  command = plan

  assert {
    condition = (
      cloudflare_account.this.settings.enforce_twofactor == true &&
      cloudflare_zero_trust_gateway_settings.this.settings.antivirus.fail_closed == true &&
      cloudflare_zero_trust_gateway_settings.this.settings.tls_decrypt.enabled == false
    )
    error_message = "Cloudflare account must enforce 2FA, fail-closed Gateway antivirus, and disabled TLS decryption (STD-OT-50, STD-OT-59)."
  }

  assert {
    condition = (
      cloudflare_r2_bucket.tfstate.location == "weur" &&
      cloudflare_r2_bucket.backups_dr.location == "weur" &&
      cloudflare_r2_bucket_lifecycle.backups_dr.rules[0].enabled == true &&
      cloudflare_r2_bucket_lifecycle.backups_dr.rules[0].abort_multipart_uploads_transition.condition.max_age == 604800
    )
    error_message = "Cloudflare R2 buckets must enforce WEUR EU data residency and 7-day incomplete multipart upload abort lifecycle (STD-OT-50, STD-OT-51, STD-OT-59)."
  }

  assert {
    condition     = alltrue([for p in cloudflare_notification_policy.this : p.enabled == true])
    error_message = "All Cloudflare security and operational notification policies must remain enabled (STD-OT-50, STD-OT-59)."
  }
}
