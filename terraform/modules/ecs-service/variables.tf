variable "name_prefix" {
  type        = string
  description = "Prefix applied to all resource names. Convention: {project}-{environment}."
}

variable "service_name" {
  type        = string
  description = "Short service identifier. Used in resource names. Example: frontend, backend."

  validation {
    condition     = contains(["frontend", "backend"], var.service_name)
    error_message = "service_name must be one of: frontend, backend."
  }
}

variable "cluster_id" {
  type        = string
  description = "ID of the ECS cluster to deploy the service into."
}

variable "cluster_name" {
  type        = string
  description = "Name of the ECS cluster. Used for CloudWatch log group naming."
}

variable "capacity_provider_name" {
  type        = string
  description = "Name of the ECS capacity provider to use for this service."
}

variable "task_execution_role_arn" {
  type        = string
  description = "ARN of the ECS task execution role. Used by ECS agent to pull images and write logs."
}

variable "task_role_arn" {
  type        = string
  description = "ARN of the ECS task role. Used by the application container at runtime."
}

variable "container_image" {
  type        = string
  description = "Full ECR image URL including tag. Example: 123456789.dkr.ecr.ap-south-1.amazonaws.com/starflix/frontend:latest."
}

variable "container_port" {
  type        = number
  description = "Port the container listens on."
}

variable "cpu" {
  type        = number
  description = "CPU units reserved for the task (1024 = 1 vCPU)."
  default     = 256
}

variable "memory" {
  type        = number
  description = "Memory in MiB reserved for the task."
  default     = 512
}

variable "desired_count" {
  type        = number
  description = "Desired number of running task instances."
  default     = 1
}

variable "target_group_arn" {
  type        = string
  description = "ARN of the ALB target group to register tasks with."
}

variable "environment_variables" {
  type = list(object({
    name  = string
    value = string
  }))
  description = "Non-sensitive environment variables injected into the container."
  default     = []
}

variable "secret_arns" {
  type = list(object({
    name      = string
    valueFrom = string
  }))
  description = "Secrets Manager or SSM ARNs injected as environment variables at container start."
  default     = []
}

variable "log_retention_days" {
  type        = number
  description = "Number of days to retain CloudWatch logs for this service."
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch retention period."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags merged onto every resource. Pass local.common_tags from the calling environment."
  default     = {}
}
