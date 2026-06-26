variable "name_prefix" {
  type        = string
  description = "Prefix applied to all resource names. Convention: {project}-{environment}."
}

variable "tags" {
  type        = map(string)
  description = "Tags merged onto every resource. Pass local.common_tags from the calling environment."
  default     = {}
}

variable "image_tag_mutability" {
  type        = string
  description = "ECR image tag mutability mode."

  default = "MUTABLE"

  validation {
    condition = contains(
      [
        "MUTABLE",
        "IMMUTABLE"
      ],
      var.image_tag_mutability
    )

    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  type        = bool
  description = "Enable vulnerability scanning when images are pushed."
  default     = true
}
