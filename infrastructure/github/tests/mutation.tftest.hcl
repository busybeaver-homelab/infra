mock_provider "github" {}

mock_provider "sops" {
  override_data {
    target = data.sops_file.secrets
    values = {
      raw = <<-EOT
        github:
          owner: "mock-owner"
          token: "mock-ghp-token-12345"
          config:
            repositories:
              infra:
                name: "infra"
                description: "Infrastructure as Code for my homelab environment"
                topics:
                  - "homelab"
                  - "infrastructure-as-code"
                  - "iac"
        opentofu:
          state_encryption_passphrase: "mock-passphrase"
      EOT
    }
  }
}

variables {
  github_token           = "mock-ghp-token-12345"
  github_owner           = "mock-owner"
  enable_prevent_destroy = false
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
        key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINhE5DoHICY85bnMIzXRGkggJ97ekZaJtzpQ6I7JgfF0 jmollner@liveperson.com"
        read_only = false
      }
      "backup-runner" = {
        title     = "backup-runner"
        key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockBackupKeyForMutationTestingUser user@test"
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
