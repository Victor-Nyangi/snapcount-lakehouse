variable "region" {
  description = "AWS region for every resource in the lake."
  type        = string
  default     = "eu-west-1"
}

variable "budget_email" {
  description = "Where AWS Budgets sends alerts. Set in the gitignored terraform.tfvars."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.budget_email))
    error_message = "budget_email must be an email address."
  }
}

variable "budget_limit_usd" {
  description = "Monthly budget in USD."
  type        = string
  default     = "5"
}

variable "ingest_date_projection_start" {
  description = "First ingest_date Athena's partition projection considers (yyyy-MM-dd)."
  type        = string
  default     = "2026-11-01"
}
