resource "tailscale_webhook" "events" {
  count         = var.webhook_endpoint_url != null && trimspace(var.webhook_endpoint_url) != "" ? 1 : 0
  endpoint_url  = var.webhook_endpoint_url
  provider_type = var.webhook_provider_type != null && trimspace(var.webhook_provider_type) != "" ? var.webhook_provider_type : null
  subscriptions = var.webhook_subscriptions
}
