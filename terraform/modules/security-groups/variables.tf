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
}

variable "backend_port" {
  type        = number
  description = "Container port the backend (Express API) listens on. ALB egress and ECS ingress are scoped to this port."
  default     = 4000
}

variable "tags" {
  type        = map(string)
  description = "Tags merged onto every security group resource. Pass local.common_tags from the calling environment."
  default     = {}
}
