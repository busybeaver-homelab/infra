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
            "tailscale_auth_key": "tskey-auth-gcp-decoy",
            "budget_alert_recipients": "ci-alerts@example.test"
          }
        EOT
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

run "verify_gcp_vpc_and_firewall" {
  command = plan

  assert {
    condition     = google_compute_network.default_vpc.name == "homelab-vpc"
    error_message = "GCP VPC network must be named homelab-vpc"
  }

  assert {
    condition     = google_compute_network.default_vpc.auto_create_subnetworks == false
    error_message = "GCP VPC network must have auto_create_subnetworks disabled"
  }

  assert {
    condition     = google_compute_subnetwork.private.ip_cidr_range == "198.51.100.0/24"
    error_message = "GCP subnet must resolve CIDR from SOPS gcp.subnet_cidr"
  }

  assert {
    condition     = google_compute_subnetwork.private.private_ip_google_access == true
    error_message = "GCP subnet must enable Private Google Access"
  }

  assert {
    condition     = google_compute_firewall.allow_tailscale_ingress.direction == "INGRESS" && contains(tolist(google_compute_firewall.allow_tailscale_ingress.target_tags), "homelab-gcp-vm")
    error_message = "Tailscale ingress firewall rule must target homelab-gcp-vm"
  }

  assert {
    condition     = google_compute_firewall.deny_all_ingress.priority == 65534
    error_message = "Deny-all ingress firewall rule must have priority 65534"
  }

  assert {
    condition     = length(google_compute_firewall.allow_breakglass_ssh) == 0
    error_message = "Breakglass SSH firewall rule must be disabled when admin_cidr is null"
  }
}

run "verify_breakglass_ssh_firewall_when_admin_cidr_set" {
  command = plan

  variables {
    admin_cidr = "203.0.113.10/32"
  }

  assert {
    condition     = length(google_compute_firewall.allow_breakglass_ssh) == 1
    error_message = "Breakglass SSH firewall rule must be created when admin_cidr is provided"
  }

  assert {
    condition     = contains(tolist(google_compute_firewall.allow_breakglass_ssh[0].source_ranges), "203.0.113.10/32")
    error_message = "Breakglass SSH firewall rule must restrict source_ranges to admin_cidr"
  }
}

run "verify_gcp_compute_instance_and_free_tier_posture" {
  command = plan

  assert {
    condition     = google_compute_instance.default.name == "gcp-default-vm"
    error_message = "Instance name must be gcp-default-vm"
  }

  assert {
    condition     = google_compute_instance.default.machine_type == "e2-micro"
    error_message = "Instance machine_type must be e2-micro"
  }

  assert {
    condition     = google_compute_instance.default.zone == "us-central1-a"
    error_message = "Instance zone must default to us-central1-a"
  }

  assert {
    condition     = google_compute_instance.default.boot_disk[0].initialize_params[0].type == "pd-standard"
    error_message = "Boot disk type must be pd-standard"
  }

  assert {
    condition     = google_compute_instance.default.boot_disk[0].initialize_params[0].size == 30
    error_message = "Boot disk size must default to 30 GB"
  }

  assert {
    condition     = data.google_compute_image.ubuntu_2604.family == "ubuntu-2604-lts-amd64" && data.google_compute_image.ubuntu_2604.project == "ubuntu-os-cloud"
    error_message = "Boot image data source must query ubuntu-2604-lts-amd64 from ubuntu-os-cloud"
  }

  assert {
    condition     = google_compute_instance.default.network_interface[0].access_config[0].network_tier == "STANDARD"
    error_message = "Instance external IP must use STANDARD network tier"
  }

  assert {
    condition     = google_compute_instance.default.shielded_instance_config[0].enable_secure_boot == true && google_compute_instance.default.shielded_instance_config[0].enable_vtpm == true && google_compute_instance.default.shielded_instance_config[0].enable_integrity_monitoring == true
    error_message = "Shielded VM must enable Secure Boot, vTPM, and Integrity Monitoring"
  }

  assert {
    condition     = google_compute_instance.default.metadata["block-project-ssh-keys"] == "TRUE" && google_compute_instance.default.metadata["serial-port-enable"] == "FALSE" && google_compute_instance.default.metadata["enable-oslogin"] == "TRUE"
    error_message = "Instance metadata must enforce block-project-ssh-keys=TRUE, serial-port-enable=FALSE, and enable-oslogin=TRUE"
  }

  assert {
    condition     = strcontains(google_compute_instance.default.metadata["user-data"], "--hostname=\"gcp-default-vm\"") && strcontains(google_compute_instance.default.metadata["user-data"], "tag:env-gcp")
    error_message = "Instance user-data must render shared cloud-init template for gcp-default-vm with tag:env-gcp"
  }

  assert {
    condition     = strcontains(google_compute_instance.default.metadata["user-data"], "--auth-key=file:/run/ts.key") && strcontains(google_compute_instance.default.metadata["user-data"], "shred -u /run/ts.key") && !strcontains(google_compute_instance.default.metadata["user-data"], "--authkey=")
    error_message = "Instance user-data must deliver Tailscale auth key via /run/ts.key and shred it after use"
  }

  assert {
    condition     = google_compute_instance.default.labels["project"] == "homelab"
    error_message = "Instance must carry mandatory project=homelab label"
  }

  assert {
    condition     = google_service_account.vm.account_id == "homelab-gcp-vm-sa"
    error_message = "Dedicated VM service account must be homelab-gcp-vm-sa"
  }
}

run "verify_computed_outputs_on_apply" {
  command = apply

  assert {
    condition     = output.vpc_network_name == "homelab-vpc"
    error_message = "GCP VPC network name output must match homelab-vpc"
  }

  assert {
    condition     = output.vpc_network_id != ""
    error_message = "GCP VPC network ID output must be computed on apply"
  }

  assert {
    condition     = output.instance_name == "gcp-default-vm"
    error_message = "Instance name output must be gcp-default-vm"
  }

  assert {
    condition     = issensitive(output.instance_private_ip) && issensitive(output.instance_public_ip) && issensitive(output.backup_hmac_secret)
    error_message = "All network and credential outputs must be marked sensitive"
  }

  assert {
    condition = (
      toset(keys(output.ansible_inventory)) == toset(["gcp-default-vm"]) &&
      output.ansible_inventory["gcp-default-vm"].group == "gcp" &&
      output.ansible_inventory["gcp-default-vm"].ansible_host == "gcp-default-vm" &&
      issensitive(output.ansible_inventory)
    )
    error_message = "ansible_inventory output must expose gcp-default-vm with group=gcp and sensitive=true"
  }
}
