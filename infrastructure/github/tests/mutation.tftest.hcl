mock_provider "github" {}
mock_provider "sops" {}
mock_provider "external" {}

override_data {
  target = data.external.sops_github_config
  values = {
    result = {
      json = <<-EOT
        {
          "repositories": {
            "infra": {
              "name": "infra",
              "description": "Infrastructure as Code for my homelab environment",
              "topics": ["homelab", "infrastructure-as-code", "iac"]
            }
          },
          "deploy_keys": {
            "work-laptop": {
              "title": "work-laptop",
              "key": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockKeyForTestingOnly0000000000000000000000",
              "read_only": false
            }
          }
        }
      EOT
    }
  }
}

override_data {
  target = data.external.sops_github_ci_age_key
  values = {
    result = {
      json = "\"\""
    }
  }
}

variables {
  state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"
  sops_age_key_ci             = format("%s%s", "AGE-SECRET-KEY-1", join("", [for _ in range(58) : "Q"])) # synthetic, format-valid test identity
  github_token                = "mock-ghp-token-12345"
  github_owner                = "mock-owner"
  enable_prevent_destroy      = false
}

run "initial_apply" {
  command = apply

  assert {
    condition     = module.repository["infra"].repository_name == "infra"
    error_message = "Initial apply must provision repository"
  }

  assert {
    condition     = module.repository["infra"].allow_squash_merge == true
    error_message = "Initial repository must enforce squash merge"
  }
}

run "mutate_deploy_keys" {
  command = plan

  variables {
    deploy_keys = {
      "work-laptop" = {
        title     = "work-laptop"
        key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockKeyForTestingOnly0000000000000000000000"
        read_only = false
      }
      "backup-runner" = {
        title     = "backup-runner"
        key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockBackupKeyForMutationTestingUser00000000"
        read_only = true
      }
    }
  }

  assert {
    condition     = contains(keys(module.repository["infra"].deploy_keys), "backup-runner")
    error_message = "Mutated deploy keys must include backup-runner"
  }

  assert {
    condition     = contains(keys(module.repository["infra"].deploy_keys), "work-laptop")
    error_message = "Work laptop deploy key must remain registered"
  }
}

run "mutate_prevent_destroy_posture" {
  command = plan

  variables {
    enable_prevent_destroy = true
  }

  assert {
    condition     = module.repository["infra"].repository_name == "infra"
    error_message = "Enabling prevent destroy must retain repository configuration"
  }
}
