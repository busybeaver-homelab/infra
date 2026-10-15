# Decrypts the canonical credentials file transiently at plan/apply time.
# Ephemeral resources are never persisted into OpenTofu state or plan artifacts (STD-OT-18).
ephemeral "sops_file" "secrets" {
  source_file = var.secrets_file_path
}

# Extracts only the `github` subtree from the canonical SOPS credentials file
# for resource attributes, keeping non-github secrets out of OpenTofu state (R2-TF-02).
data "external" "sops_github" {
  program = ["bash", "${path.module}/../../scripts/sops-subtree.sh"]
  query = {
    file    = "${path.module}/${var.secrets_file_path}"
    extract = "[\"github\"]"
  }
}
