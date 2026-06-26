############################################
# VPC
############################################

module "vpc" {
  source = "../../modules/vpc"

  name_prefix = local.name_prefix

  vpc_cidr             = var.vpc_cidr
  azs                  = local.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  single_nat_gateway = local.features.single_nat_gateway

  tags = local.common_tags
}

############################################
# Security Groups
############################################

module "security_groups" {
  source = "../../modules/security-groups"

  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id

  frontend_port = var.frontend_port
  backend_port  = var.backend_port

  tags = local.common_tags
}

############################################
# ECR
############################################

module "ecr" {
  source = "../../modules/ecr"

  name_prefix = local.name_prefix

  tags = local.common_tags
}
