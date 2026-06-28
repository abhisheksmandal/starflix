variable "name_prefix" {
  type        = string
  description = "Prefix applied to all resource names. Convention: {project}-{environment}."
}

variable "cluster_name" {
  type        = string
  description = "ECS cluster name. Used to scope CloudWatch metric alarms."
}

variable "frontend_service_name" {
  type        = string
  description = "ECS frontend service name. Used to scope alarms."
}

variable "backend_service_name" {
  type        = string
  description = "ECS backend service name. Used to scope alarms."
}

variable "frontend_alb_arn_suffix" {
  type        = string
  description = "ARN suffix of the frontend ALB. Used for ALB metric alarms."
}

variable "backend_alb_arn_suffix" {
  type        = string
  description = "ARN suffix of the backend ALB. Used for ALB metric alarms."
}

variable "frontend_tg_arn_suffix" {
  type        = string
  description = "ARN suffix of the frontend target group. Used for ALB metric alarms."
}

variable "backend_tg_arn_suffix" {
  type        = string
  description = "ARN suffix of the backend target group. Used for ALB metric alarms."
}

variable "cpu_threshold" {
  type        = number
  description = "ECS CPU utilisation % threshold to trigger alarm."
  default     = 80
}

variable "memory_threshold" {
  type        = number
  description = "ECS memory utilisation % threshold to trigger alarm."
  default     = 80
}

variable "alb_5xx_threshold" {
  type        = number
  description = "Number of ALB 5xx errors per minute to trigger alarm."
  default     = 10
}

variable "alb_response_time_threshold" {
  type        = number
  description = "ALB target response time in seconds to trigger alarm."
  default     = 5
}

variable "alarm_actions" {
  type        = list(string)
  description = "List of ARNs to notify when an alarm fires (SNS topic ARNs). Empty list = alarm only, no notification."
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Tags merged onto every resource. Pass local.common_tags from the calling environment."
  default     = {}
}
