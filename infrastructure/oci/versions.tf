terraform {
  required_version = "1.16.5"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "9.9.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.1.1"
    }
  }
}

