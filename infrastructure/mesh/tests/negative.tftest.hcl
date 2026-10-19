mock_provider "tailscale" {}
mock_provider "sops" {}

mock_provider "external" {
  override_data {
    target = data.external.sops_config
    values = {
      result = {
        json = <<-EOT
          {
            "tailnet_name": "example.ts.net",
            "contact_account_email": "account@example.test",
            "contact_support_email": "support@example.test",
            "contact_security_email": "security@example.test"
          }
        EOT
      }
    }
  }
}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
  policy_file_path            = "policy.ci.hujson.tftpl"
}

run "reject_invalid_policy_file_extension" {
  command = plan

  variables {
    policy_file_path = "policy.txt"
  }

  expect_failures = [
    var.policy_file_path,
  ]
}

run "reject_invalid_secrets_file_extension" {
  command = plan

  variables {
    secrets_file_path = "secrets/credentials.json"
  }

  expect_failures = [
    var.secrets_file_path,
  ]
}

run "reject_short_state_encryption_passphrase" {
  command = plan

  variables {
    state_encryption_passphrase = "too-short-test-passphrase"
  }

  expect_failures = [
    var.state_encryption_passphrase,
  ]
}

run "reject_placeholder_state_encryption_passphrase" {
  command = plan

  variables {
    state_encryption_passphrase = "changeme-changeme-changeme-changeme-0001"
  }

  expect_failures = [
    var.state_encryption_passphrase,
  ]
}

run "reject_unresolvable_infrastructure_device" {
  command = plan

  variables {
    infrastructure_devices = {
      "example-missing-device" = {
        tags = ["tag:type-server"]
      }
    }
    device_id_overrides = {}
  }

  expect_failures = [
    tailscale_device_tags.nodes,
    tailscale_device_key.nodes,
    tailscale_device_authorization.nodes,
  ]
}

run "reject_unresolvable_subnet_route_device" {
  command = plan

  variables {
    device_subnet_routes = {
      "example-missing-router" = ["198.51.100.0/24"]
    }
    device_id_overrides = {}
  }

  expect_failures = [
    tailscale_device_subnet_routes.routes,
  ]
}
