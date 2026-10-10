locals {
  # Alert posture (non-identifying). billing_budget_alert is intentionally unmanaged:
  # its total_spend_dollars filter is absent from the provider v5.27 schema.
  notification_policies = {
    expiring_service_token_alert = {
      name        = "Expiring Access Service Token Alert"
      description = "Cloudflare Access service token expiration notice, sent 7 days before token is set to expire"
    }
    fbm_volumetric_attack = {
      name        = "Flow-based Monitoring: Volumetric Attack"
      description = "Volumetric DDoS attacks to your infrastructure based on flow data you export to Cloudflare"
    }
    real_origin_monitoring = {
      name        = "Passive Origin Monitoring"
      description = "Cloudflare is unable to reach your origin"
    }
    bgp_hijack_notification = {
      name        = "Route Leak Detection Alert"
      description = "Alerts for BGP Hijack"
    }
    universal_ssl_event_type = {
      name        = "Universal SSL Alert"
      description = "Universal Certificate validation status, issuance, renewal, and expiration notices"
    }
    billing_usage_alert = {
      name        = "Billing Usage Alert"
      description = "Usage alert notifying when billable service limits are approached or exceeded"
    }
  }
}

resource "cloudflare_notification_policy" "this" {
  for_each = local.notification_policies

  account_id  = var.cloudflare_account_id
  name        = each.value.name
  description = each.value.description
  alert_type  = each.key
  enabled     = true

  mechanisms = {
    email = [{ id = local.cf.notification_email }]
  }
}
