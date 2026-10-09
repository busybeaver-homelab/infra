resource "cloudflare_account" "this" {
  name = local.cf.account_name

  settings = {
    enforce_twofactor = true
  }

  lifecycle {
    prevent_destroy = true
  }
}
