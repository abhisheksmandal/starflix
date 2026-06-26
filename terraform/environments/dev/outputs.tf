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
