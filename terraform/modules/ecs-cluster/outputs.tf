output "cluster_id" {
  description = "ID of the ECS cluster."
  value       = aws_ecs_cluster.this.id
}

output "cluster_name" {
  description = "Name of the ECS cluster. Pass to ECS services and CloudWatch."
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster."
  value       = aws_ecs_cluster.this.arn
}

output "capacity_provider_name" {
  description = "Name of the ECS capacity provider backed by the ASG."
  value       = aws_ecs_capacity_provider.this.name
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group managing ECS hosts."
  value       = aws_autoscaling_group.this.name
}

output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling Group."
  value       = aws_autoscaling_group.this.arn
}

output "launch_template_id" {
  description = "ID of the EC2 launch template."
  value       = aws_launch_template.ecs.id
}
