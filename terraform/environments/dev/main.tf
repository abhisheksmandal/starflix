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

############################################
# IAM
############################################

module "iam" {

  source = "../../modules/iam"


  name_prefix = local.name_prefix


  tags = local.common_tags

}

############################################
# VPC Endpoints
############################################

module "vpc_endpoints" {
  source = "../../modules/vpc-endpoints"

  name_prefix = local.name_prefix

  aws_region = var.aws_region

  vpc_id = module.vpc.vpc_id

  private_subnet_ids = module.vpc.private_subnet_ids

  private_route_table_ids = module.vpc.private_route_table_ids

  endpoint_security_group_id = module.security_groups.vpc_endpoint_sg_id

  tags = local.common_tags
}

############################################
# S3
############################################

module "s3" {
  source = "../../modules/s3"

  name_prefix    = local.name_prefix
  aws_account_id = data.aws_caller_identity.current.account_id
  aws_region     = var.aws_region

  assets_bucket_force_destroy    = var.s3_force_destroy
  artifacts_bucket_force_destroy = var.s3_force_destroy

  tags = local.common_tags
}
############################################
# DNS
############################################

module "dns" {
  source = "../../modules/dns"
  count  = local.features.enable_dns ? 1 : 0

  name_prefix = local.name_prefix
  domain_name = var.domain_name

  tags = local.common_tags
}

############################################
# ALB
############################################

module "alb" {
  source = "../../modules/alb"

  name_prefix           = local.name_prefix
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_security_group_id = module.security_groups.alb_sg_id

  acm_certificate_arn = local.features.enable_dns ? module.dns[0].acm_certificate_arn : null

  frontend_port = var.frontend_port
  backend_port  = var.backend_port

  enable_deletion_protection = var.enable_deletion_protection

  tags = local.common_tags
}

############################################
# Secrets
############################################

module "secrets" {
  source = "../../modules/secrets"

  name_prefix  = local.name_prefix
  project      = var.project
  environment  = var.environment

  recovery_window_days = var.secrets_recovery_window_days

  tags = local.common_tags
}
