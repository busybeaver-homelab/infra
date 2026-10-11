terraform {
  required_version = ">= 1.8.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 9.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.1.1"
    }
  }
}

