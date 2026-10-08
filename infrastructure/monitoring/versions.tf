terraform {
  required_version = ">= 1.8.0"

  required_providers {
    healthchecksio = {
      source  = "kristofferahl/healthchecksio"
      version = "~> 2.0"
    }
  }
}
