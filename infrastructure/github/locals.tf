locals {
  # Ephemeral: decoded canonical SOPS credentials file for provider authentication (STD-OT-18).
  sops_ephemeral = try(yamldecode(ephemeral.sops_file.secrets.raw), {})

  # Scoped `github.config` subtree extracted from SOPS for resource attributes (R2-TF-02).
  github_config = try(jsondecode(data.external.sops_github_config.result.json), {})

  # Residual limitation (R2-TF-02): `integrations/github` 6.13.0 `github_actions_environment_secret`
  # does not expose a write-only `value_wo` attribute, so `SOPS_AGE_KEY_CI` requires a non-ephemeral
  # scalar leaf extraction (`["github"]["ci_age_key"]`).
  sops_ci_age_key = try(tostring(jsondecode(data.external.sops_github_ci_age_key.result.json)), "")

  # GitHub provider credentials: use variable override if set, else read exclusively from
  # `ephemeral.sops_file.secrets` so `github.token` and `github.owner` never enter `.tfstate` (R2-TF-02).
  github_owner = var.github_owner != null && trimspace(var.github_owner) != "" ? var.github_owner : try(local.sops_ephemeral.github.owner, "")
  github_token = var.github_token != null && trimspace(var.github_token) != "" ? var.github_token : try(local.sops_ephemeral.github.token, "")

  # Repositories managed by OpenTofu: map of repository configs from SOPS.
  repositories = nonsensitive(try(local.github_config.repositories, {}))

  # Deploy keys: use explicit variable override if non-empty, else read from SOPS github.config.deploy_keys (R2-TF-08).
  deploy_keys = length(var.deploy_keys) > 0 ? var.deploy_keys : try(local.github_config.deploy_keys, {})

  # The single CI age identity (decrypts only secrets/credentials.ci.sops.yaml).
  # Source: production SOPS `github.ci_age_key`, or an explicit variable override.
  # Never read from a local keyring file and never fall back to a decoy: a missing
  # key fails the plan through the repository module's validation.
  ci_age_key = var.sops_age_key_ci != null && trimspace(var.sops_age_key_ci) != "" ? var.sops_age_key_ci : trimspace(local.sops_ci_age_key)

  # Secrets injected into the `ci` environment. PR jobs can reach this environment,
  # so it MUST NOT hold production material such as the state passphrase.
  ci_environment_secrets = merge(
    {
      SOPS_AGE_KEY_CI = local.ci_age_key
    },
    var.ci_secrets
  )

  # The `backup` and `ops` environments are restricted to `main` and MUST remain
  # disjoint from `ci` secrets; `SOPS_AGE_KEY_CI` is never injected into `backup` or `ops` (R2-CI-01).
  backup_environment_secrets = var.backup_secrets
  ops_environment_secrets    = var.ops_secrets
}
