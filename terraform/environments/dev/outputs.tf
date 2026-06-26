# ── VPC ────────────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "Primary CIDR block of the VPC."
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "IDs of public subnets (ALB, NAT Gateway), in AZ order."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of private subnets (ECS EC2 instances), in AZ order."
  value       = module.vpc.private_subnet_ids
}

output "nat_gateway_ids" {
  description = "IDs of NAT Gateways."
  value       = module.vpc.nat_gateway_ids
}

output "nat_gateway_public_ips" {
  description = "Public Elastic IP addresses of NAT Gateways. Add to external service allowlists (e.g. TMDB)."
  value       = module.vpc.nat_gateway_public_ips
}

output "availability_zones" {
  description = "Availability Zones used for subnet placement."
  value       = local.azs
}

# ── Security Groups ────────────────────────────────────────────────────────────

output "alb_security_group_id" {
  description = "ID of the ALB security group."
  value       = module.security_groups.alb_sg_id
}

output "ecs_security_group_id" {
  description = "ID of the ECS tasks security group."
  value       = module.security_groups.ecs_sg_id
}

output "vpc_endpoint_security_group_id" {
  description = "ID of the VPC interface endpoint security group."
  value       = module.security_groups.vpc_endpoint_sg_id
}

# ── ECR ────────────────────────────────────────────────────────────────────────

output "frontend_ecr_repository_url" {

  description = "Frontend Docker image repository URL."

  value = module.ecr.frontend_repository_url
}


output "backend_ecr_repository_url" {

  description = "Backend Docker image repository URL."

  value = module.ecr.backend_repository_url
}

# ── IAM ───────────────────────────────────────────────────────────────────────

output "ecs_task_execution_role_arn" {

  value = module.iam.ecs_task_execution_role_arn

}


output "ecs_task_role_arn" {

  value = module.iam.ecs_task_role_arn

}


output "ecs_instance_role_arn" {

  value = module.iam.ecs_instance_role_arn

}


output "codebuild_role_arn" {

  value = module.iam.codebuild_role_arn

}

# ── VPC Endpoints ───────────────────────────────────────────────────────────────────────

output "interface_endpoint_ids" {
  description = "Interface endpoint IDs."
  value       = module.vpc_endpoints.interface_endpoint_ids
}

output "gateway_endpoint_id" {
  description = "S3 Gateway Endpoint."
  value       = module.vpc_endpoints.s3_gateway_endpoint_id
}

# ── S3 ─────────────────────────────────────────────────────────────────────────

output "assets_bucket_name" {
  description = "Name of the S3 assets bucket."
  value       = module.s3.assets_bucket_name
}

output "assets_bucket_arn" {
  description = "ARN of the S3 assets bucket."
  value       = module.s3.assets_bucket_arn
}

output "assets_bucket_domain_name" {
  description = "Regional domain name of the assets bucket (CloudFront origin)."
  value       = module.s3.assets_bucket_domain_name
}

output "artifacts_bucket_name" {
  description = "Name of the S3 artifacts bucket."
  value       = module.s3.artifacts_bucket_name
}

output "artifacts_bucket_arn" {
  description = "ARN of the S3 artifacts bucket."
  value       = module.s3.artifacts_bucket_arn
}
# ── DNS ────────────────────────────────────────────────────────────────────────

output "route53_zone_id" {
  description = "Route 53 hosted zone ID."
  value       = local.features.enable_dns ? module.dns[0].zone_id : null
}

output "route53_name_servers" {
  description = "Name servers to delegate at your registrar."
  value       = local.features.enable_dns ? module.dns[0].zone_name_servers : null
}

output "acm_certificate_arn" {
  description = "Validated ACM certificate ARN (ap-south-1) for the ALB."
  value       = local.features.enable_dns ? module.dns[0].acm_certificate_arn : null
}

# ── ALB ────────────────────────────────────────────────────────────────────────

output "frontend_alb_dns_name" {
  description = "DNS name of the frontend ALB."
  value       = module.alb.frontend_alb_dns_name
}

output "frontend_target_group_arn" {
  description = "Frontend target group ARN for ECS service."
  value       = module.alb.frontend_target_group_arn
}

output "backend_alb_dns_name" {
  description = "DNS name of the backend ALB."
  value       = module.alb.backend_alb_dns_name
}

output "backend_target_group_arn" {
  description = "Backend target group ARN for ECS service."
  value       = module.alb.backend_target_group_arn
}

# ── Secrets ────────────────────────────────────────────────────────────────────

output "tmdb_api_key_arn" {
  description = "ARN of the TMDB API key secret."
  value       = module.secrets.tmdb_api_key_arn
}

output "strapi_app_keys_arn" {
  description = "ARN of the Strapi APP_KEYS secret."
  value       = module.secrets.strapi_app_keys_arn
}

output "strapi_jwt_secret_arn" {
  description = "ARN of the Strapi JWT_SECRET."
  value       = module.secrets.strapi_jwt_secret_arn
}

output "strapi_api_token_salt_arn" {
  description = "ARN of the Strapi API_TOKEN_SALT secret."
  value       = module.secrets.strapi_api_token_salt_arn
}

output "strapi_admin_jwt_secret_arn" {
  description = "ARN of the Strapi ADMIN_JWT_SECRET."
  value       = module.secrets.strapi_admin_jwt_secret_arn
}

output "github_token_arn" {
  description = "ARN of the GitHub token secret for CodeBuild."
  value       = module.secrets.github_token_arn
}

# ── ECS Cluster ────────────────────────────────────────────────────────────────

output "ecs_cluster_id" {
  description = "ID of the ECS cluster."
  value       = module.ecs_cluster.cluster_id
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster."
  value       = module.ecs_cluster.cluster_name
}

output "ecs_capacity_provider_name" {
  description = "Name of the ECS capacity provider."
  value       = module.ecs_cluster.capacity_provider_name
}

output "ecs_autoscaling_group_name" {
  description = "Name of the ECS Auto Scaling Group."
  value       = module.ecs_cluster.autoscaling_group_name
}
