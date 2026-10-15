# --- Data Sources & Compute (Always Free e2-micro Instance) ---

ephemeral "sops_file" "secrets" {
  source_file = var.secrets_file_path
}

data "external" "sops_config" {
  program = ["bash", "${path.module}/../../scripts/sops-subtree.sh"]
  query = {
    file    = var.secrets_file_path
    extract = "[\"gcp\"]"
  }
}

data "google_compute_image" "ubuntu_2604" {
  family  = "ubuntu-2604-lts-amd64"
  project = "ubuntu-os-cloud"
}

resource "google_service_account" "vm" {
  account_id   = "homelab-gcp-vm-sa"
  display_name = "Homelab GCP Default VM Service Account"
  description  = "Dedicated least-privilege service account for gcp-default-vm"
  project      = var.gcp_project_id
}

#trivy:ignore:AVD-GCP-0031 Approved STD-OT-49 Always-Free exception (Cloud NAT is paid; VPC/host firewalls drop unsolicited ingress)
resource "google_compute_instance" "default" {
  #checkov:skip=CKV_GCP_38:Google-managed AES-256 disk encryption is Always Free; runtime secrets use vTPM-backed systemd-creds
  #checkov:skip=CKV_GCP_40:Approved STD-OT-49 Always-Free exception; Cloud NAT is paid and VPC/host firewalls block all unsolicited ingress except UDP/41641
  name                      = "gcp-default-vm"
  machine_type              = var.gcp_instance_type
  zone                      = var.gcp_zone
  project                   = var.gcp_project_id
  tags                      = ["homelab-gcp-vm"]
  allow_stopping_for_update = true

  labels = merge(local.default_labels, { role = "compute" }, { project = "homelab" })

  # Google-managed AES-256 encryption at rest is Always Free; Cloud KMS (CMEK) is a paid
  # service and raw CSEK prevents unattended VM reboot after host maintenance. Runtime
  # secrets on disk are hardware-bound via Shielded VM vTPM 2.0 (systemd-creds host+tpm2).
  #trivy:ignore:AVD-GCP-0033
  boot_disk {
    auto_delete = true

    initialize_params {
      image  = data.google_compute_image.ubuntu_2604.self_link
      size   = var.gcp_boot_disk_size_gb
      type   = var.gcp_boot_disk_type
      labels = merge(local.default_labels, { role = "boot-disk" }, { project = "homelab" })
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id

    # STD-OT-49 approved exception: GCP Cloud NAT is a paid service; 1 Standard-Tier
    # ephemeral IPv4 is included free with the Always Free e2-micro instance while
    # VPC and host firewalls drop all unsolicited inbound traffic except UDP/41641.
    #trivy:ignore:AVD-GCP-0031
    access_config {
      network_tier = var.gcp_network_tier
    }
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  service_account {
    email = google_service_account.vm.email
    scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.metricWriter",
    ]
  }

  metadata = {
    block-project-ssh-keys = "TRUE"
    serial-port-enable     = "FALSE"
    enable-oslogin         = "TRUE"
    user-data = templatefile("${path.module}/../modules/cloud-init/cloud-init.yaml.tftpl", {
      hostname           = "gcp-default-vm"
      tailscale_auth_key = local.tailscale_auth_key
      tailscale_tags     = local.tailscale_tags
    })
  }

  lifecycle {
    prevent_destroy = var.enable_prevent_destroy
    ignore_changes = [
      metadata["user-data"],                   # cloud-init runs once; re-rendering must not replace the VM
      boot_disk[0].initialize_params[0].image, # image updates are rolled out deliberately, not on every plan
    ]
  }
}
