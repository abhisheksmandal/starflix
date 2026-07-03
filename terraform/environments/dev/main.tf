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


  github_token_secret_arn = module.secrets.github_token_arn


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

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

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
  enable_https        = local.features.enable_dns

  frontend_port = var.frontend_port
  backend_port  = var.backend_port

  enable_deletion_protection = var.enable_deletion_protection

  tags = local.common_tags

  # The ALB references the VPC's subnets/vpc_id, but NOT the Internet Gateway,
  # so Terraform would otherwise detach the IGW in parallel with deleting the
  # ALB. AWS refuses to detach an IGW while any public ENI (the ALB owns two)
  # still exists in the VPC, which deadlocks the destroy for ~20 min. Depending
  # on the whole VPC module forces every ALB resource to be destroyed first.
  depends_on = [module.vpc]
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

  github_token = var.github_token
  tmdb_api_key = var.tmdb_api_key

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

  # CloudFront needs the us-east-1 certificate, NOT the ap-south-1 ALB cert.
  acm_certificate_arn = local.features.enable_dns ? module.dns[0].cloudfront_acm_certificate_arn : null

  frontend_alb_dns_name     = module.alb.frontend_alb_dns_name
  backend_alb_dns_name      = module.alb.backend_alb_dns_name
  assets_bucket_name        = module.s3.assets_bucket_name
  assets_bucket_domain_name = module.s3.assets_bucket_domain_name

  backend_port = var.backend_port

  enable_waf = var.enable_waf

  tags = local.common_tags
}

############################################
# DNS Alias Records → CloudFront
# Point apex, www and api at the distribution.
# Lives in the environment (not the dns module)
# to avoid a dns → cloudfront → dns cycle:
# cloudfront depends on the dns cert, so these
# records must be created after both exist.
############################################

resource "aws_route53_record" "cloudfront_alias" {
  for_each = local.cloudfront_alias_records

  zone_id = module.dns[0].zone_id
  name    = each.value.name
  type    = each.value.type

  alias {
    name                   = module.cloudfront[0].distribution_domain_name
    zone_id                = module.cloudfront[0].distribution_hosted_zone_id
    evaluate_target_health = false
  }
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

  enable_autoscaling        = var.enable_service_autoscaling
  autoscaling_min_capacity  = var.service_autoscaling_min
  autoscaling_max_capacity  = var.service_autoscaling_max
  autoscaling_cpu_target    = var.service_autoscaling_cpu_target
  autoscaling_memory_target = var.service_autoscaling_memory_target

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
      value = "http://${module.alb.backend_alb_dns_name}:${var.backend_port}"
    }
  ]

  log_retention_days = var.log_retention_days

  tags = local.common_tags

  # Wait for the initial image seed so tasks don't crash-loop on first apply.
  depends_on = [null_resource.seed_images]
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

  enable_autoscaling        = var.enable_service_autoscaling
  autoscaling_min_capacity  = var.service_autoscaling_min
  autoscaling_max_capacity  = var.service_autoscaling_max
  autoscaling_cpu_target    = var.service_autoscaling_cpu_target
  autoscaling_memory_target = var.service_autoscaling_memory_target

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
      value = var.public_frontend_url != "" ? var.public_frontend_url : "http://${module.alb.frontend_alb_dns_name}"
    }
  ]

  # Only inject the TMDB key when a value is provided; otherwise the
  # backend falls back to placeholder images and the task can start.
  secret_arns = var.tmdb_api_key != "" ? [
    {
      name      = "TMDB_API_KEY"
      valueFrom = module.secrets.tmdb_api_key_arn
    }
  ] : []

  log_retention_days = var.log_retention_days

  tags = local.common_tags

  # Wait for the initial image seed so tasks don't crash-loop on first apply.
  depends_on = [null_resource.seed_images]
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

  # Public backend API URL baked into the frontend build (Option A: the
  # browser calls the backend directly instead of via the nginx proxy).
  # Prefer a public backend domain when set; otherwise the raw backend ALB DNS.
  frontend_api_url = var.public_backend_url != "" ? var.public_backend_url : "http://${module.alb.backend_alb_dns_name}:${var.backend_port}"

  frontend_cluster_name = module.ecs_cluster.cluster_name
  # Deterministic service names (not module outputs) so CodeBuild does NOT depend
  # on the ECS services — the services depend on the initial seed build instead
  # (null_resource.seed_images), which would otherwise create a dependency cycle.
  frontend_service_name = "${local.name_prefix}-svc-frontend"
  backend_service_name  = "${local.name_prefix}-svc-backend"

  aws_region     = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id

  tags = local.common_tags

  # Ensure the GitHub token secret value exists before the webhooks, which
  # validate the CodeBuild role's access to a populated secret. module.iam is
  # required too: the role's secret-read grant lives there
  # (aws_iam_role_policy_attachment.codebuild). This module only references the
  # role ARN, not that attachment, so without this Terraform tears the grant
  # down before the webhook and DeleteWebhook fails ("role does not have access
  # to retrieve secret"). Depending on the whole module forces webhooks to be
  # destroyed before the grant.
  depends_on = [module.secrets, module.iam]
}

############################################
# Initial image seed (bootstrap)
# On the first apply, ECR is empty and the
# ECS tasks would crash-loop with no image.
# Trigger both CodeBuild projects and WAIT
# for the images to land in ECR BEFORE the
# ECS services are created (they depend_on
# this resource). Runs once, on create.
############################################

resource "null_resource" "seed_images" {
  depends_on = [module.codebuild]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      REGION="${var.aws_region}"
      PROJECTS=("${module.codebuild.frontend_project_name}" "${module.codebuild.backend_project_name}")
      IDS=()
      for P in "$${PROJECTS[@]}"; do
        ID=$(aws codebuild start-build --project-name "$P" --region "$REGION" --query 'build.id' --output text)
        echo "Started initial build for $P: $ID"
        IDS+=("$ID")
      done
      for ID in "$${IDS[@]}"; do
        echo "Waiting for build $ID to finish..."
        while true; do
          S=$(aws codebuild batch-get-builds --ids "$ID" --region "$REGION" --query 'builds[0].buildStatus' --output text)
          case "$S" in
            SUCCEEDED)   echo "  $ID SUCCEEDED"; break ;;
            IN_PROGRESS) sleep 15 ;;
            *)           echo "  $ID ended with status: $S" >&2; exit 1 ;;
          esac
        done
      done
      echo "Seed images pushed to ECR."
    EOT
  }
}
