variable "name_prefix" {
  type        = string
  description = "Prefix applied to all resource names. Convention: {project}-{environment}."
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC to create the ALBs in."
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "IDs of public subnets to place the ALBs in. Minimum two AZs required."

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "At least two public subnet IDs are required for ALB multi-AZ placement."
  }
}

variable "alb_security_group_id" {
  type        = string
  description = "ID of the ALB security group."
}

variable "acm_certificate_arn" {
  type        = string
  description = "ACM certificate ARN for the frontend HTTPS listener. Used as the listener certificate value when enable_https is true."
  default     = null
}

variable "backend_acm_certificate_arn" {
  type        = string
  description = "ACM certificate ARN for the backend HTTPS listener. Used as the listener certificate value when enable_https is true."
  default     = null
}

variable "enable_https" {
  type        = bool
  description = "Create the HTTPS listener (and redirect HTTP→HTTPS). Must be a plan-time-known boolean — the ACM cert ARN itself is unknown until apply, so listener count/for_each cannot depend on it. Pass local.features.enable_dns."
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

variable "health_check_path_frontend" {
  type        = string
  description = "Health check path for the frontend target group."
  default     = "/"
}

variable "health_check_path_backend" {
  type        = string
  description = "Health check path for the backend target group."
  default     = "/health"
}

variable "enable_deletion_protection" {
  type        = bool
  description = "Enable ALB deletion protection. Always true in prod."
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Tags merged onto every resource. Pass local.common_tags from the calling environment."
  default     = {}
}
