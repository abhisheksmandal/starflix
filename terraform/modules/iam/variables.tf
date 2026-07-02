variable "name_prefix" {
  type        = string
  description = "Prefix applied to IAM role names."
}


variable "tags" {
  type        = map(string)
  description = "Common resource tags."
  default     = {}
}


variable "assets_bucket_arn" {
  type        = string
  description = "S3 assets bucket ARN accessible by application containers."
  default     = ""
}


variable "github_token_secret_arn" {
  type        = string
  description = "Secrets Manager ARN of the GitHub token used by CodeBuild source auth and webhooks."
  default     = ""
}
