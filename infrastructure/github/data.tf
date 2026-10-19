# Decrypts the canonical credentials file transiently at plan/apply time.
# Ephemeral resources are never persisted into OpenTofu state or plan artifacts (STD-OT-18).
ephemeral "sops_file" "secrets" {
  source_file = var.secrets_file_path
}

# Scoped external data source — extracts only the `github.config` subtree via
# `sops -d --extract '["github"]["config"]'` so repository configuration can drive
# resource arguments without pulling `github.token`, `github.owner`, or unrelated SOPS
# domains into OpenTofu state (R2-TF-02).
data "external" "sops_github_config" {
  program = ["bash", "${path.module}/../../scripts/sops-subtree.sh"]

  query = {
    file    = "${path.module}/${var.secrets_file_path}"
    extract = "[\"github\"][\"config\"]"
  }
}

# Residual limitation (R2-TF-02): `integrations/github` 6.13.0 `github_actions_environment_secret`
# has no `value_wo` write-only attribute and rejects ephemeral values in `value` (and `for_each`).
# Extract only the scalar `github.ci_age_key` leaf so `github.token` and `github.owner` remain
# exclusively in `ephemeral.sops_file.secrets`.
data "external" "sops_github_ci_age_key" {
  program = ["bash", "${path.module}/../../scripts/sops-subtree.sh"]

  query = {
    file    = "${path.module}/${var.secrets_file_path}"
    extract = "[\"github\"][\"ci_age_key\"]"
  }
}
