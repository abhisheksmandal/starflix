output "frontend_project_name" {
  description = "Name of the frontend CodeBuild project."
  value       = aws_codebuild_project.frontend.name
}

output "frontend_project_arn" {
  description = "ARN of the frontend CodeBuild project."
  value       = aws_codebuild_project.frontend.arn
}

output "backend_project_name" {
  description = "Name of the backend CodeBuild project."
  value       = aws_codebuild_project.backend.name
}

output "backend_project_arn" {
  description = "ARN of the backend CodeBuild project."
  value       = aws_codebuild_project.backend.arn
}

output "frontend_build_log_group" {
  description = "CloudWatch log group for frontend builds."
  value       = aws_cloudwatch_log_group.frontend_build.name
}

output "backend_build_log_group" {
  description = "CloudWatch log group for backend builds."
  value       = aws_cloudwatch_log_group.backend_build.name
}
