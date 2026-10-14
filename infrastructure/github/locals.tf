locals {
  # Sensitive: decoded canonical SOPS credentials file.
  sops_data = yamldecode(data.sops_file.secrets.raw)

  # GitHub provider credentials: use variable override if set, else read from SOPS.
  github_owner = var.github_owner != "" ? var.github_owner : try(local.sops_data.github.owner, "")
  github_token = var.github_token != "" ? var.github_token : try(local.sops_data.github.token, "")

  # Repositories managed by OpenTofu: map of repository configs from SOPS.
  repositories = nonsensitive(try(local.sops_data.github.config.repositories, {}))

  # The single CI age identity (decrypts only secrets/credentials.ci.sops.yaml).
  # Source: production SOPS `github.ci_age_key`, or an explicit variable override.
  # Never read from a local keyring file and never fall back to a decoy: a missing
  # key fails the plan through the repository module's validation.
  ci_age_key = var.sops_age_key_ci != "" ? var.sops_age_key_ci : trimspace(try(local.sops_data.github.ci_age_key, ""))

  # Secrets injected into the `ci` environment. PR jobs can reach this environment,
  # so it MUST NOT hold production material such as the state passphrase.
  ci_environment_secrets = merge(
    {
      SOPS_AGE_KEY_CI = local.ci_age_key
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
