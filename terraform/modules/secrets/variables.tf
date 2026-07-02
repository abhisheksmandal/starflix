variable "name_prefix" {
  type        = string
  description = "Prefix applied to all resource names. Convention: {project}-{environment}."
}

variable "project" {
  type        = string
  description = "Project name. Used to construct Secrets Manager paths: {project}/{environment}/{name}."
}

variable "environment" {
  type        = string
  description = "Deployment environment. Used to construct Secrets Manager paths."

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be one of: dev, stage, prod."
  }
}

variable "recovery_window_days" {
  type        = number
  description = "Number of days Secrets Manager waits before permanently deleting a secret. Set 0 to disable (dev only)."
  default     = 7

  validation {
    condition     = var.recovery_window_days == 0 || (var.recovery_window_days >= 7 && var.recovery_window_days <= 30)
    error_message = "recovery_window_days must be 0 (disabled) or between 7 and 30."
  }
}

variable "tmdb_api_key" {
  type        = string
  description = "TMDB API key for backend metadata enrichment. Leave empty to set out-of-band; the backend then falls back to placeholder images."
  default     = ""
  sensitive   = true
}

variable "github_token" {
  type        = string
  description = "GitHub personal access token for CodeBuild source auth. Leave empty to set the value out-of-band instead of via Terraform."
  default     = ""
  sensitive   = true
}

variable "frontend_url" {
  type        = string
  description = "Public URL of the frontend. Stored as SSM parameter for backend container config."
  default     = ""
}

variable "backend_url" {
  type        = string
  description = "Public URL of the Strapi backend API. Stored as SSM parameter for frontend container config."
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Tags merged onto every resource. Pass local.common_tags from the calling environment."
  default     = {}
}
