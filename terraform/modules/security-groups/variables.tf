variable "name_prefix" {
  type        = string
  description = "Prefix applied to all security group names. Convention: {project}-{environment}."
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC to create security groups in."
}

variable "frontend_port" {
  type        = number
  description = "Container port the frontend (nginx) listens on. ALB egress and ECS ingress are scoped to this port."
  default     = 80

  validation {
    condition     = var.frontend_port > 0 && var.frontend_port < 65536
    error_message = "frontend_port must be between 1 and 65535."
  }
}

variable "backend_port" {
  type        = number
  description = "Container port the backend (Express API) listens on. ALB egress and ECS ingress are scoped to this port."
  default     = 4000

  validation {
    condition     = var.backend_port > 0 && var.backend_port < 65536
    error_message = "backend_port must be between 1 and 65535."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags merged onto every security group resource. Pass local.common_tags from the calling environment."
  default     = {}
}
