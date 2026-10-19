mock_provider "google" {
  override_data {
    target = data.google_compute_image.ubuntu_2604
    values = {
      self_link = "projects/ubuntu-os-cloud/global/images/ubuntu-2604-lts-amd64-v20261014"
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
            "subnet_cidr": "198.51.100.0/24",
            "budget_alert_recipients": "ci-alerts@example.test"
          }
        EOT
      }
    }
  }

  override_data {
    target = data.external.sops_tailscale_auth_key
    values = {
      result = {
        json = "\"tskey-auth-gcp-decoy\""
      }
    }
  }
}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
  gcp_project_id              = "mock-gcp-project-12345"
  gcp_region                  = "us-central1"
  gcp_zone                    = "us-central1-a"
  gcp_billing_account_id      = "012345-6789AB-CDEF01"
  enable_prevent_destroy      = false
}

run "initial_apply" {
  command = apply

  assert {
    condition     = google_compute_network.default_vpc.name == "homelab-vpc"
    error_message = "Initial apply must provision homelab-vpc"
  }

  assert {
    condition     = google_compute_instance.default.name == "gcp-default-vm"
    error_message = "Initial apply must provision gcp-default-vm"
  }
}

run "mutate_region_and_zone" {
  command = plan

  variables {
    gcp_region = "us-east1"
    gcp_zone   = "us-east1-b"
  }

  assert {
    condition     = var.gcp_region == "us-east1" && google_compute_instance.default.zone == "us-east1-b"
    error_message = "Mutated region and zone must be accepted within Always Free tier"
  }
}

run "mutate_labels_and_admin_cidr" {
  command = plan

  variables {
    admin_cidr = "203.0.113.55/32"
    default_labels = {
      project     = "homelab"
      environment = "test-mutation"
    }
  }

  assert {
    condition     = length(google_compute_firewall.allow_breakglass_ssh) == 1
    error_message = "Breakglass SSH firewall rule must be planned when admin_cidr is added"
  }

  assert {
    condition     = lookup(local.default_labels, "project", "") == "homelab"
    error_message = "Mandatory project label must be homelab in local.default_labels"
  }
}

run "mutate_region_to_us_west1" {
  command = plan

  variables {
    gcp_region = "us-west1"
    gcp_zone   = "us-west1-a"
  }

  assert {
    condition     = var.gcp_region == "us-west1" && google_compute_instance.default.zone == "us-west1-a"
    error_message = "Region mutation to us-west1 must be accepted within Always Free tier"
  }
}

run "mutate_with_budget_and_labels" {
  command = apply

  variables {
    gcp_billing_account_id  = "654321-BA9876-10FEDC"
    budget_alert_recipients = ["ops-mutated@example.test"]
    default_labels = {
      project     = "homelab"
      environment = "mutation-stage"
      managed_by  = "opentofu"
    }
  }

  assert {
    condition     = google_billing_budget.monthly_spend_limit.billing_account == "654321-BA9876-10FEDC"
    error_message = "Billing account on budget resource must match mutated variable input"
  }

  assert {
    condition     = lookup(local.default_labels, "managed_by", "") == "opentofu"
    error_message = "Additional label must be preserved in local.default_labels"
  }
}
