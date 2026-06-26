variable "name_prefix" {
  type        = string
  description = "Prefix applied to all resource names. Convention: {project}-{environment}."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "IDs of private subnets to place ECS EC2 instances in."

  validation {
    condition     = length(var.private_subnet_ids) >= 1
    error_message = "At least one private subnet ID is required."
  }
}

variable "ecs_security_group_id" {
  type        = string
  description = "ID of the ECS tasks security group. Attached to EC2 instances."
}

variable "ecs_instance_role_name" {
  type        = string
  description = "Name of the IAM role to attach to EC2 ECS instances via instance profile."
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type for ECS hosts."
  default     = "t3.small"
}

variable "ami_id" {
  type        = string
  description = "Custom AMI ID for ECS hosts. Leave empty to use the latest ECS-optimised Amazon Linux 2 AMI fetched from SSM."
  default     = ""
}

variable "desired_capacity" {
  type        = number
  description = "Desired number of EC2 instances in the ASG."
  default     = 1
}

variable "min_size" {
  type        = number
  description = "Minimum number of EC2 instances in the ASG."
  default     = 1
}

variable "max_size" {
  type        = number
  description = "Maximum number of EC2 instances in the ASG."
  default     = 3
}

variable "root_volume_size_gb" {
  type        = number
  description = "Size in GiB of the root EBS volume on each ECS host."
  default     = 30
}

variable "enable_container_insights" {
  type        = bool
  description = "Enable CloudWatch Container Insights on the ECS cluster."
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Tags merged onto every resource. Pass local.common_tags from the calling environment."
  default     = {}
}
