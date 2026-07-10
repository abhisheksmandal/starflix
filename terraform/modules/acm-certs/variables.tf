variable "name_prefix" {
  type        = string
  description = "Prefix applied to all resource names. Convention: {project}-{environment}."
}

variable "frontend_domain_name" {
  type        = string
  description = "Public hostname for the frontend ALB certificate. Example: abhishek-frontend.1020dev.com."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9\\-\\.]+[a-z0-9]$", var.frontend_domain_name))
    error_message = "frontend_domain_name must be a valid domain name (lowercase, hyphens and dots allowed)."
  }
}

variable "backend_domain_name" {
  type        = string
  description = "Public hostname for the backend ALB certificate. Example: abhishek-backend.1020dev.com."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9\\-\\.]+[a-z0-9]$", var.backend_domain_name))
    error_message = "backend_domain_name must be a valid domain name (lowercase, hyphens and dots allowed)."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags merged onto every resource. Pass local.common_tags from the calling environment."
  default     = {}
}
