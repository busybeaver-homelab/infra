terraform {
  required_version = "1.16.6"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.28.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.4.2"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.4.1"
    }
  }
}
