terraform {
  required_version = "1.16.6"

  required_providers {
    external = {
      source  = "hashicorp/external"
      version = "2.4.2"
    }
    google = {
      source  = "hashicorp/google"
      version = "8.7.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.4.1"
    }
  }
}
