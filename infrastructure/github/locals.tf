locals {
  # Sensitive: decoded canonical SOPS credentials file.
  sops_data = yamldecode(data.sops_file.secrets.raw)

  # GitHub provider credentials: use variable override if set, else read from SOPS.
  github_owner = var.github_owner != "" ? var.github_owner : try(local.sops_data.github.owner, "")
  github_token = var.github_token != "" ? var.github_token : try(local.sops_data.github.token, "")

  # Repositories managed by OpenTofu: map of repository configs from SOPS.
  repositories = nonsensitive(try(local.sops_data.github.config.repositories, {}))

  # CI age private key resolution: explicit variable override > local age keys file > fallback decoy.
  ci_age_key = coalesce(
    var.sops_age_key_ci != "" ? var.sops_age_key_ci : null,
    fileexists(pathexpand(var.sops_age_key_file)) ? trimspace(file(pathexpand(var.sops_age_key_file))) : null,
    "AGE-SECRET-KEY-SYNTHETIC-DECOY-DUMMY-VALUE-FOR-TESTS"
  )

  # Centralized environment secrets injected into repositories
  ci_environment_secrets = merge(
    {
      SOPS_AGE_KEY_CI            = local.ci_age_key
      TOFU_ENCRYPTION_PASSPHRASE = try(local.sops_data.opentofu.state_encryption_passphrase, "")
    },
    var.ci_secrets
  )

  backup_environment_secrets = merge(
    {
      SOPS_AGE_KEY_CI = local.ci_age_key
    },
    var.backup_secrets
  )
}
