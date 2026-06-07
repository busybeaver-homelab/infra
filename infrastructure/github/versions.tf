terraform {
  required_version = ">= 1.8.0"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }

  backend "gcs" {
    # Bucket name to be provided dynamically during 'tofu init -backend-config=...'
    prefix = "github/state"
  }
}
