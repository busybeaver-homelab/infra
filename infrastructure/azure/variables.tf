variable "azure_subscription_id" {
  type        = string
  description = "The Azure subscription ID."
  sensitive   = true
}


variable "monthly_budget_amount" {
  type        = number
  description = "Monthly budget limit in USD to cap annual spending below $2000."
  default     = 165

  validation {
    condition     = var.monthly_budget_amount > 0 && var.monthly_budget_amount <= 165
    error_message = "The monthly_budget_amount must be greater than 0 and not exceed $165 to guarantee annual spending stays below $2000."
  }
}

variable "budget_contact_emails" {
  type        = list(string)
  description = "List of email addresses to notify when budget thresholds are exceeded."
  default     = []

  validation {
    condition = alltrue([
      for email in var.budget_contact_emails : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All contact emails must be valid email addresses."
  }
}
