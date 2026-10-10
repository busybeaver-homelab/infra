# Decrypts the canonical credentials file at plan time; repository identifying configuration
# lives under github.config.repositories (see secrets/README.md).
data "sops_file" "secrets" {
  source_file = var.secrets_file_path
}
