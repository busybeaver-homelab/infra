terraform {
  required_version = "~> 1.13.1"

  required_providers {
    healthchecksio = {
      source  = "kristofferahl/healthchecksio"
      version = "2.3.0"
    }
  }
}
