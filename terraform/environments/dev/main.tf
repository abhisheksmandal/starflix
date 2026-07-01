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

  name_prefix = local.name_prefix
  project     = var.project
  environment = var.environment

  recovery_window_days = var.secrets_recovery_window_days

  tags = local.common_tags
}

############################################
# ECS Cluster
############################################

module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  name_prefix            = local.name_prefix
  private_subnet_ids     = module.vpc.private_subnet_ids
  ecs_security_group_id  = module.security_groups.ecs_sg_id
  ecs_instance_role_name = module.iam.ecs_instance_role_name

  instance_type    = var.ecs_instance_type
  ami_id           = var.ecs_ami_id
  desired_capacity = var.ecs_desired_capacity
  min_size         = var.ecs_min_size
  max_size         = var.ecs_max_size

  enable_container_insights = var.enable_container_insights

  tags = local.common_tags
}

############################################
# CloudFront
############################################

module "cloudfront" {
  source = "../../modules/cloudfront"
  count  = local.features.enable_cloudfront ? 1 : 0

  name_prefix = local.name_prefix
  domain_name = var.domain_name

  acm_certificate_arn = local.features.enable_dns ? module.dns[0].acm_certificate_arn : null

  frontend_alb_dns_name     = module.alb.frontend_alb_dns_name
  backend_alb_dns_name      = module.alb.backend_alb_dns_name
  assets_bucket_name        = module.s3.assets_bucket_name
  assets_bucket_domain_name = module.s3.assets_bucket_domain_name

  backend_port = var.backend_port

  enable_waf = var.enable_waf

  tags = local.common_tags
}

############################################
# ECS Service — Frontend (Node.js)
############################################

module "ecs_service_frontend" {
  source = "../../modules/ecs-service"

  name_prefix  = local.name_prefix
  service_name = "frontend"
  cluster_id   = module.ecs_cluster.cluster_id
  cluster_name = module.ecs_cluster.cluster_name

  capacity_provider_name  = module.ecs_cluster.capacity_provider_name
  task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  task_role_arn           = module.iam.ecs_task_role_arn

  container_image = "${module.ecr.frontend_repository_url}:${var.frontend_image_tag}"
  container_port  = var.frontend_port

  cpu           = var.frontend_cpu
  memory        = var.frontend_memory
  desired_count = var.ecs_desired_capacity

  target_group_arn = module.alb.frontend_target_group_arn

  environment_variables = [
    {
      name  = "NODE_ENV"
      value = var.environment
    },
    {
      name  = "PORT"
      value = tostring(var.frontend_port)
    },
    {
      name  = "BACKEND_URL"
      value = "http://${module.alb.backend_alb_dns_name}:${var.backend_port}/api"
    }
  ]

  log_retention_days = var.log_retention_days

  tags = local.common_tags
}

############################################
# ECS Service — Backend (Strapi)
############################################

module "ecs_service_backend" {
  source = "../../modules/ecs-service"

  name_prefix  = local.name_prefix
  service_name = "backend"
  cluster_id   = module.ecs_cluster.cluster_id
  cluster_name = module.ecs_cluster.cluster_name

  capacity_provider_name  = module.ecs_cluster.capacity_provider_name
  task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  task_role_arn           = module.iam.ecs_task_role_arn

  container_image = "${module.ecr.backend_repository_url}:${var.backend_image_tag}"
  container_port  = var.backend_port

  cpu           = var.backend_cpu
  memory        = var.backend_memory
  desired_count = var.ecs_desired_capacity

  target_group_arn = module.alb.backend_target_group_arn

  environment_variables = [
    {
      name  = "NODE_ENV"
      value = var.environment
    },
    {
      name  = "PORT"
      value = tostring(var.backend_port)
    },
    {
    name  = "FRONTEND_URL"
    value = "http://${module.alb.frontend_alb_dns_name}"
    }
  ]

  secret_arns = [
    {
      name      = "TMDB_API_KEY"
      valueFrom = module.secrets.tmdb_api_key_arn
    }
  ]

  log_retention_days = var.log_retention_days

  tags = local.common_tags
}

############################################
# CloudWatch
############################################

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  name_prefix = local.name_prefix

  cluster_name          = module.ecs_cluster.cluster_name
  frontend_service_name = module.ecs_service_frontend.service_name
  backend_service_name  = module.ecs_service_backend.service_name

  frontend_alb_arn_suffix = module.alb.frontend_alb_arn_suffix
  backend_alb_arn_suffix  = module.alb.backend_alb_arn_suffix
  frontend_tg_arn_suffix  = module.alb.frontend_target_group_arn_suffix
  backend_tg_arn_suffix   = module.alb.backend_target_group_arn_suffix

  cpu_threshold               = var.cloudwatch_cpu_threshold
  memory_threshold            = var.cloudwatch_memory_threshold
  alb_5xx_threshold           = var.cloudwatch_5xx_threshold
  alb_response_time_threshold = var.cloudwatch_response_time_threshold

  tags = local.common_tags
}

############################################
# CodeBuild
############################################

module "codebuild" {
  source = "../../modules/codebuild"

  name_prefix = local.name_prefix

  codebuild_role_arn    = module.iam.codebuild_role_arn
  artifacts_bucket_name = module.s3.artifacts_bucket_name

  github_repo_url         = var.github_repo_url
  github_branch           = var.github_branch
  github_token_secret_arn = module.secrets.github_token_arn

  frontend_repo_url = module.ecr.frontend_repository_url
  backend_repo_url  = module.ecr.backend_repository_url

  frontend_cluster_name = module.ecs_cluster.cluster_name
  frontend_service_name = module.ecs_service_frontend.service_name
  backend_service_name  = module.ecs_service_backend.service_name

  aws_region     = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id

  tags = local.common_tags
}
