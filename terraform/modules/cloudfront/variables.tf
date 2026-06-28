variable "name_prefix" {
  type        = string
  description = "Prefix applied to all resource names. Convention: {project}-{environment}."
}

variable "domain_name" {
  type        = string
  description = "Root domain name. Example: starflix.com."
}

variable "acm_certificate_arn" {
  type        = string
  description = "ACM certificate ARN (ap-south-1) covering apex + wildcard. Required when aliases are set."
  default     = null
}

variable "frontend_alb_dns_name" {
  type        = string
  description = "DNS name of the frontend ALB. Used as CloudFront HTTP origin for starflix.com and www."
}

variable "backend_alb_dns_name" {
  type        = string
  description = "DNS name of the backend ALB. Used as CloudFront HTTP origin for api.starflix.com."
}

variable "assets_bucket_name" {
  type        = string
  description = "Name of the S3 assets bucket. Used as CloudFront S3 origin for /static/* paths."
}

variable "assets_bucket_domain_name" {
  type        = string
  description = "Regional domain name of the S3 assets bucket."
}

variable "backend_port" {
  type        = number
  description = "Port the backend ALB listens on."
  default     = 4000
}

variable "enable_waf" {
  type        = bool
  description = "Attach a WAF ACL to the CloudFront distribution. Prod only."
  default     = false
}

variable "waf_acl_arn" {
  type        = string
  description = "ARN of the WAF ACL to attach. Required when enable_waf is true."
  default     = null
}

variable "price_class" {
  type        = string
  description = "CloudFront price class. PriceClass_200 covers Asia, US and Europe."
  default     = "PriceClass_200"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be one of: PriceClass_100, PriceClass_200, PriceClass_All."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags merged onto every resource. Pass local.common_tags from the calling environment."
  default     = {}
}
