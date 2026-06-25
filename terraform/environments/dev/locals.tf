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
  }
}
