resource "tailscale_contacts" "homelab" {
  account {
    email = local.contact_account_email
  }
  support {
    email = local.contact_support_email
  }
  security {
    email = local.contact_security_email
  }
}
