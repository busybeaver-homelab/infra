mock_provider "tailscale" {}

mock_provider "sops" {
  override_data {
    target = data.sops_file.secrets
    values = {
      raw = <<-EOT
        tailscale:
          client_id: "ts-client-id-decoy"
          client_secret: "ts-client-secret-decoy"
          config:
            tailnet_name: "example.ts.net"
            contact_account_email: "account@example.test"
            contact_support_email: "support@example.test"
            contact_security_email: "security@example.test"
      EOT
    }
  }
}

variables {
  policy_file_path = "policy.ci.hujson.tftpl"
}

run "extended_default_plan" {
  command = plan

  assert {
    condition     = tailscale_dns_preferences.homelab.magic_dns == true
    error_message = "MagicDNS should be enabled by default."
  }

  assert {
    condition     = tailscale_tailnet_settings.homelab.devices_approval_on == true
    error_message = "Device approval must be enabled by default."
  }

  assert {
    condition     = tailscale_tailnet_settings.homelab.posture_identity_collection_on == false
    error_message = "Posture identity collection must remain false on free tier."
  }

  assert {
    condition     = tailscale_tailnet_settings.homelab.regional_routing_on == false
    error_message = "Regional routing must remain false on free tier."
  }

  assert {
    condition     = tailscale_tailnet_settings.homelab.acls_externally_managed_on == true
    error_message = "ACL external management must be enabled by default."
  }

  assert {
    condition     = tailscale_tailnet_settings.homelab.acls_external_link != null && length(tailscale_tailnet_settings.homelab.acls_external_link) > 0
    error_message = "ACL external link must be populated when externally managed."
  }

  assert {
    condition     = strcontains(tailscale_acl.homelab.acl, "nextdns:947d9e")
    error_message = "Tailscale ACL policy must include NextDNS attribute in nodeAttrs."
  }

  assert {
    condition     = strcontains(tailscale_acl.homelab.acl, "tag:device-laptop")
    error_message = "Tailscale ACL policy must include tag:device-laptop in nodeAttrs."
  }

  assert {
    condition     = length(tailscale_dns_search_paths.homelab.search_paths) == 0
    error_message = "Search paths should default to empty list."
  }

  assert {
    condition     = length(tailscale_dns_nameservers.homelab) == 0
    error_message = "DNS nameservers resource should be 0 by default to prevent overriding NextDNS."
  }

  assert {
    condition     = length(tailscale_webhook.events) == 0
    error_message = "Webhook resource should default to 0."
  }

  assert {
    condition     = length(tailscale_dns_split_nameservers.routes) == 0
    error_message = "Split DNS routes should be empty by default."
  }

  assert {
    condition     = length(tailscale_tailnet_key.roles) == 0
    error_message = "Role auth keys should be empty by default."
  }

  assert {
    condition     = length(tailscale_device_tags.nodes) == 10
    error_message = "Infrastructure device tags must manage all 10 hosts."
  }

  assert {
    condition     = length(tailscale_device_key.nodes) == 10
    error_message = "Infrastructure device key management must cover 10 hosts."
  }

  assert {
    condition     = length(tailscale_device_authorization.nodes) == 10
    error_message = "Infrastructure device authorization must cover 10 hosts."
  }

  assert {
    condition     = length(tailscale_device_subnet_routes.routes) == 0
    error_message = "Subnet routes must default to empty."
  }

  assert {
    condition     = contains(tailscale_device_tags.nodes["unifi-gateway"].tags, "tag:type-network")
    error_message = "unifi-gateway must have tag:type-network."
  }

  assert {
    condition     = tailscale_device_key.nodes["unifi-gateway"].key_expiry_disabled == true
    error_message = "unifi-gateway key expiry must be disabled by default."
  }

  assert {
    condition     = tailscale_device_authorization.nodes["unifi-gateway"].authorized == true
    error_message = "unifi-gateway must be authorized by default."
  }

  assert {
    condition     = contains(tailscale_device_tags.nodes["gcp-default-vm"].tags, "tag:env-gcp")
    error_message = "gcp-default-vm must contain tag:env-gcp."
  }

  assert {
    condition     = contains(tailscale_device_tags.nodes["adguard-home"].tags, "tag:svc-adguard")
    error_message = "adguard-home must contain tag:svc-adguard."
  }

  assert {
    condition     = contains(tailscale_device_tags.nodes["beszel"].tags, "tag:svc-beszel")
    error_message = "beszel must contain tag:svc-beszel."
  }

  assert {
    condition     = contains(tailscale_device_tags.nodes["synology-nas1"].tags, "tag:type-nas")
    error_message = "synology-nas1 must contain tag:type-nas."
  }
}

run "extended_custom_dns_and_keys" {
  command = plan

  variables {
    dns_nameservers  = ["1.1.1.1", "1.0.0.1"]
    dns_search_paths = ["homelab.internal"]
    dns_split_nameservers = {
      "corp.example.internal" = ["198.51.100.53"]
    }
    auth_keys = {
      "k8s-operator" = {
        reusable      = true
        ephemeral     = true
        preauthorized = true
        expiry        = 86400
        description   = "k8s operator key"
        tags          = ["tag:type-server", "tag:env-oci"]
      }
    }
    device_subnet_routes = {
      "unifi-gateway" = ["198.51.100.0/24", "203.0.113.0/24"]
    }
  }

  assert {
    condition     = length(tailscale_dns_nameservers.homelab) == 1
    error_message = "DNS nameservers resource should be 1 when configured."
  }

  assert {
    condition     = tolist(tailscale_dns_nameservers.homelab[0].nameservers) == tolist(["1.1.1.1", "1.0.0.1"])
    error_message = "DNS nameservers must match input."
  }

  assert {
    condition     = tolist(tailscale_dns_search_paths.homelab.search_paths) == tolist(["homelab.internal"])
    error_message = "Search paths must match configured value."
  }

  assert {
    condition     = toset(tailscale_dns_split_nameservers.routes["corp.example.internal"].nameservers) == toset(["198.51.100.53"])
    error_message = "Split DNS route nameservers must match configured value."
  }

  assert {
    condition     = tailscale_tailnet_key.roles["k8s-operator"].reusable == true
    error_message = "k8s-operator auth key must be reusable."
  }

  assert {
    condition     = tailscale_tailnet_key.roles["k8s-operator"].ephemeral == true
    error_message = "k8s-operator auth key must be ephemeral."
  }

  assert {
    condition     = tailscale_tailnet_key.roles["k8s-operator"].expiry == 86400
    error_message = "k8s-operator auth key expiry must be 86400."
  }

  assert {
    condition     = tailscale_tailnet_key.roles["k8s-operator"].tags == toset(["tag:type-server", "tag:env-oci"])
    error_message = "k8s-operator tags must match configured set."
  }

  assert {
    condition     = toset(tailscale_device_subnet_routes.routes["unifi-gateway"].routes) == toset(["198.51.100.0/24", "203.0.113.0/24"])
    error_message = "Subnet routes for unifi-gateway must match configured list."
  }
}

run "extended_device_id_overrides" {
  command = plan

  variables {
    device_id_overrides = {
      "adguard-home"   = "id-adguard"
      "beszel"         = "id-beszel"
      "gcp-default-vm" = "id-gcp"
      "heide-apple-tv" = "id-atv"
      "node-red"       = "id-nodered"
      "nuc-kvm"        = "id-nuckvm"
      "nuc-linux"      = "id-nuclinux"
      "nuc-windows"    = "id-nucwin"
      "synology-nas1"  = "id-synology"
      "unifi-gateway"  = "override-unifi-id"
    }
  }

  assert {
    condition     = tailscale_device_tags.nodes["unifi-gateway"].device_id == "override-unifi-id"
    error_message = "Device ID override must take precedence for tags."
  }

  assert {
    condition     = tailscale_device_key.nodes["unifi-gateway"].device_id == "override-unifi-id"
    error_message = "Device ID override must take precedence for key expiry."
  }

  assert {
    condition     = tailscale_device_authorization.nodes["unifi-gateway"].device_id == "override-unifi-id"
    error_message = "Device ID override must take precedence for authorization."
  }
}

run "extended_apply_and_sensitive_outputs" {
  command = apply

  variables {
    device_id_overrides = {
      "adguard-home"   = "id-adguard"
      "beszel"         = "id-beszel"
      "gcp-default-vm" = "id-gcp"
      "heide-apple-tv" = "id-atv"
      "node-red"       = "id-nodered"
      "nuc-kvm"        = "id-nuckvm"
      "nuc-linux"      = "id-nuclinux"
      "nuc-windows"    = "id-nucwin"
      "synology-nas1"  = "id-synology"
      "unifi-gateway"  = "id-unifi"
    }
  }

  assert {
    condition     = issensitive(output.users)
    error_message = "output.users must be sensitive."
  }

  assert {
    condition     = issensitive(output.monitored_devices)
    error_message = "output.monitored_devices must be sensitive."
  }

  assert {
    condition     = issensitive(output.role_auth_keys)
    error_message = "output.role_auth_keys must be sensitive."
  }

  assert {
    condition     = issensitive(output.devices)
    error_message = "output.devices must be sensitive."
  }

  assert {
    condition     = issensitive(output.auth_key_bootstrap)
    error_message = "output.auth_key_bootstrap must be sensitive."
  }

  assert {
    condition     = issensitive(output.webhook_endpoint_url)
    error_message = "output.webhook_endpoint_url must be sensitive."
  }

  assert {
    condition     = issensitive(output.webhook_secret)
    error_message = "output.webhook_secret must be sensitive."
  }
}

run "reject_invalid_dns_nameservers" {
  command = plan

  variables {
    dns_nameservers = ["invalid-ip-format"]
  }

  expect_failures = [
    var.dns_nameservers,
  ]
}

run "reject_invalid_split_nameservers" {
  command = plan

  variables {
    dns_split_nameservers = {
      "example.internal" = ["not.an.ip.address"]
    }
  }

  expect_failures = [
    var.dns_split_nameservers,
  ]
}

run "reject_invalid_auth_key_tags" {
  command = plan

  variables {
    auth_keys = {
      "bad-key" = {
        reusable      = false
        ephemeral     = true
        preauthorized = false
        expiry        = 3600
        description   = "bad key"
        tags          = ["no-tag-prefix"]
      }
    }
  }

  expect_failures = [
    var.auth_keys,
  ]
}

run "reject_invalid_subnet_cidr" {
  command = plan

  variables {
    device_subnet_routes = {
      "unifi-gateway" = ["999.999.999.999/99"]
    }
  }

  expect_failures = [
    var.device_subnet_routes,
  ]
}

run "reject_invalid_device_tags" {
  command = plan

  variables {
    infrastructure_devices = {
      "unifi-gateway" = {
        tags = ["missing-tag-prefix"]
      }
    }
  }

  expect_failures = [
    var.infrastructure_devices,
  ]
}

run "extended_optional_webhook" {
  command = plan

  variables {
    webhook_endpoint_url  = "https://example.test/tailnet-events"
    webhook_provider_type = "slack"
  }

  assert {
    condition     = length(tailscale_webhook.events) == 1
    error_message = "Webhook resource should be instantiated when URL is provided."
  }

  assert {
    condition     = tailscale_webhook.events[0].provider_type == "slack"
    error_message = "Webhook provider type should match input."
  }
}

run "reject_invalid_webhook_url" {
  command = plan

  variables {
    webhook_endpoint_url = "http://insecure.test"
  }

  expect_failures = [
    var.webhook_endpoint_url,
  ]
}

run "reject_invalid_policy_file_extension" {
  command = plan

  variables {
    policy_file_path = "policy.invalid"
  }

  expect_failures = [
    var.policy_file_path,
  ]
}

run "reject_acl_external_management_disabled" {
  command = plan

  variables {
    acls_externally_managed_on = false
    acls_external_link         = ""
  }

  expect_failures = [
    check.free_tier_invariants,
  ]
}

run "reject_invalid_acls_external_link" {
  command = plan

  variables {
    acls_external_link = "ftp://invalid-url.com"
  }

  expect_failures = [
    var.acls_external_link,
  ]
}
