terraform {
  required_version = "~> 1.13.1"

  required_providers {
    # Typical homelab providers (e.g. Proxmox, UniFi)
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.116.0"
    }
  }
}

