############################################
# Current AWS Region
# Used in log configuration.
############################################

data "aws_region" "current" {}

############################################
# CloudWatch Log Group
# One log group per service.
# Log stream prefix matches container name.
############################################

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.cluster_name}/${var.service_name}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name    = "/ecs/${var.cluster_name}/${var.service_name}"
    Service = var.service_name
  })
}

############################################
# ECS Task Definition
# Defines the container spec — image, ports,
# CPU/memory, environment, secrets, logging.
############################################

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name_prefix}-td-${var.service_name}"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]

  execution_role_arn = var.task_execution_role_arn
  task_role_arn      = var.task_role_arn

  cpu    = var.cpu
  memory = var.memory

  container_definitions = jsonencode([
    {
      name      = var.service_name
      image     = var.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = 0
          protocol      = "tcp"
        }
      ]

      environment = var.environment_variables

      secrets = var.secret_arns

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = var.service_name
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-td-${var.service_name}"
    Service = var.service_name
  })
}

############################################
# ECS Service
# Maintains the desired count of tasks,
# registers them with the ALB target group,
# and uses the capacity provider for
# placement on EC2 instances.
############################################

resource "aws_ecs_service" "this" {
  name    = "${var.name_prefix}-svc-${var.service_name}"
  cluster = var.cluster_id

  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider_name
    base              = 1
    weight            = 100
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.service_name
    container_port   = var.container_port
  }

  health_check_grace_period_seconds = 60

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-svc-${var.service_name}"
    Service = var.service_name
  })
}
