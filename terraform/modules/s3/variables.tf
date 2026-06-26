variable "name_prefix" {
  type        = string
  description = "Prefix applied to all resource names. Convention: {project}-{environment}."
}

variable "aws_account_id" {
  type        = string
  description = "AWS account ID. Used to construct globally unique S3 bucket names."
}

variable "aws_region" {
  type        = string
  description = "AWS region. Used to construct globally unique S3 bucket names."
}

variable "assets_bucket_force_destroy" {
  type        = bool
  description = "Allow Terraform to destroy the assets bucket even when it contains objects. Set true only for dev/test."
  default     = false
}

variable "artifacts_bucket_force_destroy" {
  type        = bool
  description = "Allow Terraform to destroy the artifacts bucket even when it contains objects. Set true only for dev/test."
  default     = false
}

variable "noncurrent_version_retention_days" {
  type        = number
  description = "Number of days to retain noncurrent object versions before expiry."
  default     = 30

  validation {
    condition     = var.noncurrent_version_retention_days >= 1
    error_message = "noncurrent_version_retention_days must be at least 1."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags merged onto every resource. Pass local.common_tags from the calling environment."
  default     = {}
}
