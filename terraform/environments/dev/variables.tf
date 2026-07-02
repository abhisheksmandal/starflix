variable "project" {
  type        = string
  description = "Project name. Used in all resource names and tags."
  default     = "starflix"
}

variable "environment" {
  type        = string
  description = "Deployment environment."

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be one of: dev, stage, prod."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region for all resources."
  default     = "ap-south-1"
}

variable "vpc_cidr" {
  type        = string
  description = "Primary CIDR block for the VPC."
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets (ALB, NAT Gateway). One entry per desired AZ."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 1
    error_message = "At least one public subnet CIDR is required."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets (ECS EC2). Must have the same number of entries as public_subnet_cidrs."
  default     = ["10.0.11.0/24", "10.0.12.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 1
    error_message = "At least one private subnet CIDR is required."
  }
}

variable "single_nat_gateway" {
  type        = bool
  description = "Deploy one NAT Gateway shared by all private subnets instead of one per AZ. Reduces cost at the expense of AZ-level HA. Recommended for dev."
  default     = false
}

variable "frontend_port" {
  type        = number
  description = "Container port the frontend (nginx) listens on."
  default     = 80
}

variable "backend_port" {
  type        = number
  description = "Container port the backend (Express API) listens on."
  default     = 4000
}

variable "owner" {
  type        = string
  description = "Team responsible for these resources. Applied as a tag."
  default     = "platform-team"
}

variable "cost_center" {
  type        = string
  description = "Cost center code for FinOps attribution."
  default     = "eng-infra"
}

variable "s3_force_destroy" {
  type        = bool
  description = "Allow Terraform to destroy S3 buckets even when they contain objects. Set true only for dev."
  default     = false
}
variable "domain_name" {
  type        = string
  description = "Root domain for Route 53 hosted zone and ACM certificates."
  default     = "starflix.com"
}

variable "enable_dns" {
  type        = bool
  description = "Deploy Route 53 hosted zone and ACM certificate. Disable to skip DNS provisioning."
  default     = false
}
variable "enable_deletion_protection" {
  type        = bool
  description = "Enable ALB deletion protection. Should be true in prod only."
  default     = false
}

variable "secrets_recovery_window_days" {
  type        = number
  description = "Days before permanent secret deletion. Set 0 for dev to allow fast destroy."
  default     = 0
}

variable "ecs_instance_type" {
  type        = string
  description = "EC2 instance type for ECS hosts."
  default     = "t3.small"
}

variable "ecs_ami_id" {
  type        = string
  description = "Custom AMI ID for ECS hosts. Leave empty to use latest ECS-optimised Amazon Linux 2 AMI."
  default     = ""
}

variable "ecs_desired_capacity" {
  type        = number
  description = "Desired number of ECS EC2 instances."
  default     = 1
}

variable "ecs_min_size" {
  type        = number
  description = "Minimum number of ECS EC2 instances."
  default     = 1
}

variable "ecs_max_size" {
  type        = number
  description = "Maximum number of ECS EC2 instances."
  default     = 3
}

variable "enable_container_insights" {
  type        = bool
  description = "Enable CloudWatch Container Insights on the ECS cluster."
  default     = false
}

variable "enable_cloudfront" {
  type        = bool
  description = "Deploy CloudFront distribution. Disable for dev to save cost."
  default     = false
}

variable "enable_waf" {
  type        = bool
  description = "Attach WAF ACL to CloudFront. Prod only."
  default     = false
}

variable "frontend_image_tag" {
  type        = string
  description = "Docker image tag for the frontend container."
  default     = "latest"
}

variable "backend_image_tag" {
  type        = string
  description = "Docker image tag for the backend container."
  default     = "latest"
}

variable "frontend_cpu" {
  type        = number
  description = "CPU units for the frontend task (256 = 0.25 vCPU)."
  default     = 256
}

variable "frontend_memory" {
  type        = number
  description = "Memory in MiB for the frontend task."
  default     = 512
}

variable "backend_cpu" {
  type        = number
  description = "CPU units for the backend (Strapi) task."
  default     = 256
}

variable "backend_memory" {
  type        = number
  description = "Memory in MiB for the backend (Strapi) task."
  default     = 768
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days for ECS services."
  default     = 7
}

variable "cloudwatch_cpu_threshold" {
  type        = number
  description = "ECS CPU % threshold for CloudWatch alarm."
  default     = 80
}

variable "cloudwatch_memory_threshold" {
  type        = number
  description = "ECS memory % threshold for CloudWatch alarm."
  default     = 80
}

variable "cloudwatch_5xx_threshold" {
  type        = number
  description = "ALB 5xx error count per minute threshold for CloudWatch alarm."
  default     = 10
}

variable "cloudwatch_response_time_threshold" {
  type        = number
  description = "ALB target response time in seconds threshold for CloudWatch alarm."
  default     = 5
}

variable "github_repo_url" {
  type        = string
  description = "HTTPS URL of the GitHub repository. Example: https://github.com/org/starflix."
}

variable "github_branch" {
  type        = string
  description = "Git branch CodeBuild builds from."
  default     = "main"
}

variable "github_token" {
  type        = string
  description = "GitHub PAT (scopes: repo, admin:repo_hook) for CodeBuild source auth and webhooks. Set via a gitignored *.tfvars file or TF_VAR_github_token; leave empty to manage the secret value out-of-band."
  default     = ""
  sensitive   = true
}

variable "tmdb_api_key" {
  type        = string
  description = "TMDB API key for backend metadata enrichment. Leave empty to run with placeholder images. Set via a gitignored *.tfvars file or TF_VAR_tmdb_api_key."
  default     = ""
  sensitive   = true
}
