terraform {
  required_version = "1.16.6"

  required_providers {
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

