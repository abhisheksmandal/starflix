data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "${var.project}-${var.environment}"

  # Slice to only as many AZs as we have subnet CIDRs.
  azs = slice(
    data.aws_availability_zones.available.names,
    0,
    length(var.public_subnet_cidrs)
  )

  common_tags = {
    Project            = var.project
    Environment        = var.environment
    ManagedBy          = "terraform"
    Owner              = var.owner
    CostCenter         = var.cost_center
    GitRepo            = "org/starflix-infra"
    DataClassification = "internal"
  }

  # Infrastructure feature flags — controls module behaviour per environment.
  features = {
    single_nat_gateway = var.single_nat_gateway
    enable_dns         = var.enable_dns
    enable_cloudfront  = var.enable_cloudfront
  }

  # Public alias records are only meaningful when both the hosted zone exists
  # and there is a CloudFront distribution to point them at.
  create_dns_records = var.enable_dns && var.enable_cloudfront

  # Hostnames served by CloudFront (all covered by the apex + wildcard cert).
  cloudfront_hostnames = {
    apex = var.domain_name
    www  = "www.${var.domain_name}"
    api  = "api.${var.domain_name}"
  }

  # One A and one AAAA alias record per hostname (CloudFront is IPv6-enabled).
  cloudfront_alias_records = local.create_dns_records ? {
    for pair in setproduct(keys(local.cloudfront_hostnames), ["A", "AAAA"]) :
    "${pair[0]}_${pair[1]}" => {
      name = local.cloudfront_hostnames[pair[0]]
      type = pair[1]
    }
  } : {}
}
