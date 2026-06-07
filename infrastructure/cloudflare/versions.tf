terraform {
  required_version = ">= 1.8.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }

  backend "gcs" {
    # Bucket name to be provided dynamically during 'tofu init -backend-config=...'
    prefix = "cloudflare/state"
  }
}
