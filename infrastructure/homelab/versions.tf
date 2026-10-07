terraform {
  required_version = ">= 1.8.0"

  required_providers {
    # Typical homelab providers (e.g. Proxmox, UniFi)
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.60"
    }
  }
}

