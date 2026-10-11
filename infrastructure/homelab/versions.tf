terraform {
  required_version = "1.16.5"

  required_providers {
    # Typical homelab providers (e.g. Proxmox, UniFi)
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.109.0"
    }
  }
}

