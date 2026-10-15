provider "cloudflare" {
  api_token = var.cloudflare_api_token != "" ? var.cloudflare_api_token : try(yamldecode(ephemeral.sops_file.secrets.raw).cloudflare.api_token, "")
}
