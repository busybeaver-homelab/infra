terraform {
  required_version = "~> 1.13.1"

  required_providers {
    nextdns = {
      source  = "amalucelli/nextdns"
      version = "0.2.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.4.1"
    }
  }
}
