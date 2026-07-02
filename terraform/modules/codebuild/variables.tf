variable "name_prefix" {
  type        = string
  description = "Prefix applied to all resource names. Convention: {project}-{environment}."
}

variable "codebuild_role_arn" {
  type        = string
  description = "ARN of the IAM role for CodeBuild projects."
}

variable "artifacts_bucket_name" {
  type        = string
  description = "S3 bucket name for storing CodeBuild artifacts."
}

variable "github_repo_url" {
  type        = string
  description = "HTTPS URL of the GitHub repository. Example: https://github.com/org/starflix."
}

variable "github_branch" {
  type        = string
  description = "Git branch to build from."
  default     = "main"
}

variable "github_token_secret_arn" {
  type        = string
  description = "ARN of the Secrets Manager secret containing the GitHub token."
}

variable "frontend_repo_url" {
  type        = string
  description = "ECR repository URL for the frontend image."
}

variable "frontend_api_url" {
  type        = string
  description = "Public base URL of the backend API, baked into the frontend build as VITE_API_URL so the browser calls the backend directly. Example: http://backend-alb:4000."
  default     = ""
}

variable "backend_repo_url" {
  type        = string
  description = "ECR repository URL for the backend image."
}

variable "frontend_cluster_name" {
  type        = string
  description = "ECS cluster name. Used for rolling deploy after build."
}

variable "frontend_service_name" {
  type        = string
  description = "ECS frontend service name. Used for rolling deploy after build."
}

variable "backend_service_name" {
  type        = string
  description = "ECS backend service name. Used for rolling deploy after build."
}

variable "aws_region" {
  type        = string
  description = "AWS region. Used in buildspec environment variables."
}

variable "aws_account_id" {
  type        = string
  description = "AWS account ID. Used to construct ECR registry URL."
}

variable "build_timeout_minutes" {
  type        = number
  description = "Build timeout in minutes."
  default     = 30
}

variable "compute_type" {
  type        = string
  description = "CodeBuild compute type."
  default     = "BUILD_GENERAL1_SMALL"

  validation {
    condition     = contains(["BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE"], var.compute_type)
    error_message = "compute_type must be BUILD_GENERAL1_SMALL, BUILD_GENERAL1_MEDIUM, or BUILD_GENERAL1_LARGE."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags merged onto every resource. Pass local.common_tags from the calling environment."
  default     = {}
}
