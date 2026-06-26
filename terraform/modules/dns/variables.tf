variable "name_prefix" {
  type        = string
  description = "Prefix applied to all resource names. Convention: {project}-{environment}."
}

variable "domain_name" {
  type        = string
  description = "Root domain name for the hosted zone and ACM certificates. Example: starflix.com."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9\\-\\.]+[a-z0-9]$", var.domain_name))
    error_message = "domain_name must be a valid domain name (lowercase, hyphens and dots allowed)."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags merged onto every resource. Pass local.common_tags from the calling environment."
  default     = {}
}
