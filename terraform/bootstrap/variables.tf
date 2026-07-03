variable "project" {
  type        = string
  description = "Project name. Used in resource names and tags."
  default     = "starflix"
}

variable "aws_region" {
  type        = string
  description = "AWS region for the bootstrap resources."
  default     = "ap-south-1"
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
  default = {
    Project   = "starflix"
    ManagedBy = "terraform"
  }
}
