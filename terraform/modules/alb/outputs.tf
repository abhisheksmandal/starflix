# ── Frontend ALB ───────────────────────────────────────────────────────────────

output "frontend_alb_arn" {
  description = "ARN of the frontend ALB."
  value       = aws_lb.frontend.arn
}

output "frontend_alb_dns_name" {
  description = "DNS name of the frontend ALB. Used as CloudFront origin."
  value       = aws_lb.frontend.dns_name
}

output "frontend_alb_zone_id" {
  description = "Hosted zone ID of the frontend ALB. Used for Route 53 alias records."
  value       = aws_lb.frontend.zone_id
}

output "frontend_alb_arn_suffix" {
  description = "ARN suffix of the frontend ALB. Used for CloudWatch metrics."
  value       = aws_lb.frontend.arn_suffix
}

output "frontend_target_group_arn" {
  description = "ARN of the frontend target group. Pass to ECS service."
  value       = aws_lb_target_group.frontend.arn
}

output "frontend_target_group_arn_suffix" {
  description = "ARN suffix of the frontend target group. Used for CloudWatch metrics."
  value       = aws_lb_target_group.frontend.arn_suffix
}

# ── Backend ALB ────────────────────────────────────────────────────────────────

output "backend_alb_arn" {
  description = "ARN of the backend ALB."
  value       = aws_lb.backend.arn
}

output "backend_alb_dns_name" {
  description = "DNS name of the backend ALB. Used by frontend ECS tasks to reach the API."
  value       = aws_lb.backend.dns_name
}

output "backend_alb_zone_id" {
  description = "Hosted zone ID of the backend ALB."
  value       = aws_lb.backend.zone_id
}

output "backend_alb_arn_suffix" {
  description = "ARN suffix of the backend ALB. Used for CloudWatch metrics."
  value       = aws_lb.backend.arn_suffix
}

output "backend_target_group_arn" {
  description = "ARN of the backend target group. Pass to ECS service."
  value       = aws_lb_target_group.backend.arn
}

output "backend_target_group_arn_suffix" {
  description = "ARN suffix of the backend target group. Used for CloudWatch metrics."
  value       = aws_lb_target_group.backend.arn_suffix
}
