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

output "cloudfront_acm_certificate_arn" {
  description = "Validated ACM certificate ARN (us-east-1) for CloudFront."
  value       = local.features.enable_dns ? module.dns[0].cloudfront_acm_certificate_arn : null
}

# ── ACM (Cloudflare-DNS path) ───────────────────────────────────────────────────

output "frontend_acm_certificate_arn" {
  description = "ARN of the frontend ALB's ACM certificate. Usable immediately; PENDING_VALIDATION until the Cloudflare CNAME below is added."
  value       = var.enable_https ? module.acm[0].frontend_certificate_arn : null
}

output "backend_acm_certificate_arn" {
  description = "ARN of the backend ALB's ACM certificate. Usable immediately; PENDING_VALIDATION until the Cloudflare CNAME below is added."
  value       = var.enable_https ? module.acm[0].backend_certificate_arn : null
}

output "acm_validation_records" {
  description = "DNS validation records to add in Cloudflare (type CNAME, proxy status DNS-only) so both certificates move from PENDING_VALIDATION to ISSUED."
  value       = var.enable_https ? module.acm[0].validation_records : null
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

# output "strapi_app_keys_arn" {
#   description = "ARN of the Strapi APP_KEYS secret."
#   value       = module.secrets.strapi_app_keys_arn
# }
# 
# output "strapi_jwt_secret_arn" {
#   description = "ARN of the Strapi JWT_SECRET."
#   value       = module.secrets.strapi_jwt_secret_arn
# }
# 
# output "strapi_api_token_salt_arn" {
#   description = "ARN of the Strapi API_TOKEN_SALT secret."
#   value       = module.secrets.strapi_api_token_salt_arn
# }
# 
# output "strapi_admin_jwt_secret_arn" {
#   description = "ARN of the Strapi ADMIN_JWT_SECRET."
#   value       = module.secrets.strapi_admin_jwt_secret_arn
# }

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

# ── CloudFront ─────────────────────────────────────────────────────────────────

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID."
  value       = local.features.enable_cloudfront ? module.cloudfront[0].distribution_id : null
}

output "cloudfront_domain_name" {
  description = "CloudFront domain name. Point starflix.com, www and api CNAME records here."
  value       = local.features.enable_cloudfront ? module.cloudfront[0].distribution_domain_name : null
}

output "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN."
  value       = local.features.enable_cloudfront ? module.cloudfront[0].distribution_arn : null
}

# ── ECS Services ───────────────────────────────────────────────────────────────

output "frontend_service_name" {
  description = "Name of the frontend ECS service."
  value       = module.ecs_service_frontend.service_name
}

output "frontend_task_definition_arn" {
  description = "ARN of the frontend task definition."
  value       = module.ecs_service_frontend.task_definition_arn
}

output "frontend_log_group_name" {
  description = "CloudWatch log group for the frontend service."
  value       = module.ecs_service_frontend.log_group_name
}

output "backend_service_name" {
  description = "Name of the backend ECS service."
  value       = module.ecs_service_backend.service_name
}

output "backend_task_definition_arn" {
  description = "ARN of the backend task definition."
  value       = module.ecs_service_backend.task_definition_arn
}

output "backend_log_group_name" {
  description = "CloudWatch log group for the backend service."
  value       = module.ecs_service_backend.log_group_name
}

# ── CloudWatch ─────────────────────────────────────────────────────────────────

output "cloudwatch_dashboard_url" {
  description = "CloudWatch dashboard URL."
  value       = module.cloudwatch.dashboard_url
}

output "cloudwatch_dashboard_name" {
  description = "CloudWatch dashboard name."
  value       = module.cloudwatch.dashboard_name
}

# ── CodeBuild ──────────────────────────────────────────────────────────────────

output "frontend_codebuild_project" {
  description = "Name of the frontend CodeBuild project."
  value       = module.codebuild.frontend_project_name
}

output "backend_codebuild_project" {
  description = "Name of the backend CodeBuild project."
  value       = module.codebuild.backend_project_name
}
