mock_provider "cloudflare" {
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
  enable_prevent_destroy      = false
}

run "initial_apply" {
  command = apply

  assert {
    condition     = cloudflare_r2_bucket.tfstate.name == "homelab-infra-tfstate"
    error_message = "Initial apply must provision state bucket"
  }

  assert {
    condition     = cloudflare_r2_bucket.backups_dr.location == "weur"
    error_message = "Initial backup bucket location must default to weur"
  }
}

run "mutate_backup_bucket_name" {
  command = plan

  variables {
    r2_backup_bucket_name = "homelab-backups-dr-secondary"
  }

  assert {
    condition     = cloudflare_r2_bucket.backups_dr.name == "homelab-backups-dr-secondary"
    error_message = "Mutated bucket name must reflect in plan"
  }

  assert {
    condition     = cloudflare_r2_bucket.tfstate.name == "homelab-infra-tfstate"
    error_message = "Primary tfstate bucket name must remain unchanged"
  }
}

run "mutate_prevent_destroy_posture" {
  command = plan

  variables {
    enable_prevent_destroy = true
  }

  assert {
    condition     = output.r2_backup_bucket_name == "homelab-backups-dr"
    error_message = "Enabling prevent destroy must retain resource definitions"
  }
}
