resource "cloudflare_zero_trust_organization" "this" {
  account_id                                  = var.cloudflare_account_id
  name                                        = local.cf.zero_trust.organization.name
  auth_domain                                 = local.cf.zero_trust.organization.auth_domain
  login_design                                = local.cf.zero_trust.organization.login_design
  is_ui_read_only                             = false
  allow_authenticate_via_warp                 = false
  deny_unmatched_requests                     = false
  deny_unmatched_requests_exempted_zone_names = []

  lifecycle {
    prevent_destroy = var.enable_prevent_destroy
    # Live value is {enabled = false, action = null, inactivity_threshold_days = null}; the v5.27
    # schema requires action/threshold, so the disabled state is not representable in config.
    ignore_changes = [service_token_inactivity]
  }
}

resource "cloudflare_zero_trust_access_identity_provider" "otp" {
  account_id = var.cloudflare_account_id
  name       = "" # live OTP provider carries an empty name
  type       = "onetimepin"
  config     = {}
}

resource "cloudflare_zero_trust_gateway_settings" "this" {
  account_id = var.cloudflare_account_id

  settings = {
    antivirus = {
      enabled_download_phase = true
      enabled_upload_phase   = true
      fail_closed            = true
    }
    tls_decrypt = {
      enabled = false
    }
  }
}

resource "cloudflare_zero_trust_dns_location" "default" {
  account_id     = var.cloudflare_account_id
  name           = local.cf.zero_trust.dns_location.name
  client_default = true
  ecs_support    = false
  networks       = []
  max_ttl        = { mode = "inherit" }
}

resource "cloudflare_zero_trust_device_default_profile" "this" {
  account_id                     = var.cloudflare_account_id
  allow_mode_switch              = false
  allow_updates                  = false
  allowed_to_leave               = true
  auto_connect                   = 0
  captive_portal                 = 180
  disable_auto_fallback          = false
  exclude_office_ips             = false
  register_interface_ip_with_dns = true
  sccm_vpn_boundary_support      = false
  switch_locked                  = false
  tunnel_protocol                = ""
  support_url                    = ""
  service_mode_v2                = { mode = "1dot1" }

  # Split-tunnel exclude list (identifying -> SOPS). Entries carry either `address` (IP/CIDR) or
  # `host` (domain); empty descriptions are null upstream.
  exclude = [
    for e in local.cf.zero_trust.split_tunnel_excludes : {
      address     = try(e.address, null)
      host        = try(e.host, null)
      description = try(e.description, null) == "" ? null : try(e.description, null)
    }
  ]
}
