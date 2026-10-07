variable "azure_subscription_id" {
  type        = string
  description = "The Azure subscription ID."
  sensitive   = true
}


variable "budget_contact_emails" {
  type        = list(string)
  description = "List of email addresses to notify when budget thresholds are exceeded."
  default     = []
}
