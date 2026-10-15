terraform {
  required_version = "1.16.6"

  required_providers {
    external = {
      source  = "hashicorp/external"
      version = "2.3.5"
    }
    oci = {
      source  = "oracle/oci"
      version = "9.9.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.4.1"
    }
  }
}

