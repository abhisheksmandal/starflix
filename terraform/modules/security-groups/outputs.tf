output "alb_sg_id" {
  description = "ID of the ALB security group."
  value       = aws_security_group.alb.id
}

output "alb_sg_arn" {
  description = "ARN of the ALB security group."
  value       = aws_security_group.alb.arn
}

output "ecs_sg_id" {
  description = "ID of the ECS tasks security group."
  value       = aws_security_group.ecs.id
}

output "ecs_sg_arn" {
  description = "ARN of the ECS tasks security group."
  value       = aws_security_group.ecs.arn
}

output "vpc_endpoint_sg_id" {
  description = "ID of the VPC interface endpoint security group."
  value       = aws_security_group.vpc_endpoints.id
}

output "vpc_endpoint_sg_arn" {
  description = "ARN of the VPC interface endpoint security group."
  value       = aws_security_group.vpc_endpoints.arn
}
