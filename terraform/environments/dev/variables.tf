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
  default     = "us-east-1"
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
