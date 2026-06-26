output "ecs_task_execution_role_arn" {

  description = "ECS task execution role ARN."

  value = aws_iam_role.ecs_task_execution.arn
}


output "ecs_task_role_arn" {

  description = "ECS application task role ARN."

  value = aws_iam_role.ecs_task.arn
}


output "ecs_instance_role_name" {

  description = "ECS EC2 instance role name."

  value = aws_iam_role.ecs_instance.name
}


output "ecs_instance_role_arn" {

  description = "ECS EC2 instance role ARN."

  value = aws_iam_role.ecs_instance.arn
}


output "codebuild_role_arn" {

  description = "CodeBuild service role ARN."

  value = aws_iam_role.codebuild.arn
}
