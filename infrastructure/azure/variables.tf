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
  description = "List of email addresses to notify when budget thresholds are exceeded (at least one required)."
  sensitive   = true
  nullable    = false

  validation {
    condition = (
      length(var.budget_contact_emails) >= 1 &&
      alltrue([
        for email in var.budget_contact_emails : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
      ])
    )
    error_message = "At least one valid budget contact email address must be provided."
  }
}

variable "state_encryption_passphrase" {
  type        = string
  description = "State and plan encryption passphrase. Source: production SOPS opentofu.state_encryption_passphrase. No default, so a missing value fails closed."
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(var.state_encryption_passphrase) >= 32
    error_message = "Set TF_VAR_state_encryption_passphrase from SOPS (opentofu.state_encryption_passphrase); it must be at least 32 characters."
  }

  validation {
    condition     = !can(regex("(?i)(default|changeme|placeholder|example)", var.state_encryption_passphrase))
    error_message = "state_encryption_passphrase looks like a placeholder; supply the real value from SOPS."
  }
}
