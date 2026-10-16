terraform {
  required_version = "~> 1.13.1"

  required_providers {
    external = {
      source  = "hashicorp/external"
      version = "2.4.2"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.29.2"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.4.1"
    }
  }
}
