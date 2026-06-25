variable "name_prefix" {
  type        = string
  description = "Prefix applied to all resource names. Convention: {project}-{environment}."
}

variable "vpc_cidr" {
  type        = string
  description = "Primary CIDR block for the VPC."

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "azs" {
  type        = list(string)
  description = "Availability Zone names to deploy into. Drives the number of subnets created."

  validation {
    condition     = length(var.azs) >= 1
    error_message = "At least one Availability Zone is required."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets. Length must equal length of azs."

  validation {
    condition     = length(var.public_subnet_cidrs) >= 1
    error_message = "At least one public subnet CIDR is required."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets. Length must equal length of azs."

  validation {
    condition     = length(var.private_subnet_cidrs) >= 1
    error_message = "At least one private subnet CIDR is required."
  }
}

variable "single_nat_gateway" {
  type        = bool
  description = "Create one shared NAT Gateway instead of one per AZ. Not suitable for production HA."
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Tags merged onto every resource. Pass local.common_tags from the calling environment."
  default     = {}
}
