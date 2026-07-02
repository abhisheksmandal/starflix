############################################
# Locals
############################################

locals {
  ecr_registry = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

############################################
# CodeBuild — Frontend (Node.js)
# Builds the Node.js frontend image,
# pushes to ECR, then triggers ECS
# rolling deploy.
############################################

resource "aws_codebuild_project" "frontend" {
  name          = "${var.name_prefix}-frontend-build"
  description   = "Builds and deploys the Starflix Node.js frontend."
  service_role  = var.codebuild_role_arn
  build_timeout = var.build_timeout_minutes

  artifacts {
    type      = "S3"
    location  = var.artifacts_bucket_name
    path      = "frontend"
    packaging = "ZIP"
  }

  environment {
    compute_type                = var.compute_type
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true

    environment_variable {
      name  = "AWS_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "ECR_REGISTRY"
      value = local.ecr_registry
    }

    environment_variable {
      name  = "ECR_REPO_URL"
      value = var.frontend_repo_url
    }

    environment_variable {
      name  = "ECS_CLUSTER"
      value = var.frontend_cluster_name
    }

    environment_variable {
      name  = "ECS_SERVICE"
      value = var.frontend_service_name
    }

    # Baked into the SPA at build time so the browser calls the public
    # backend ALB directly (no in-VPC nginx proxy hairpin).
    environment_variable {
      name  = "VITE_API_URL"
      value = var.frontend_api_url
    }
  }

  source {
    type            = "GITHUB"
    location        = var.github_repo_url
    git_clone_depth = 1
    buildspec       = "frontend/buildspec.yml"

    auth {
      type     = "SECRETS_MANAGER"
      resource = var.github_token_secret_arn
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/codebuild/${var.name_prefix}/frontend"
      stream_name = "build"
    }
  }

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-frontend-build"
    Service = "frontend"
  })
}

############################################
# CodeBuild — Backend (Strapi)
# Builds the Strapi backend image,
# pushes to ECR, then triggers ECS
# rolling deploy.
############################################

resource "aws_codebuild_project" "backend" {
  name          = "${var.name_prefix}-backend-build"
  description   = "Builds and deploys the Starflix Strapi backend."
  service_role  = var.codebuild_role_arn
  build_timeout = var.build_timeout_minutes

  artifacts {
    type      = "S3"
    location  = var.artifacts_bucket_name
    path      = "backend"
    packaging = "ZIP"
  }

  environment {
    compute_type                = var.compute_type
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true

    environment_variable {
      name  = "AWS_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "ECR_REGISTRY"
      value = local.ecr_registry
    }

    environment_variable {
      name  = "ECR_REPO_URL"
      value = var.backend_repo_url
    }

    environment_variable {
      name  = "ECS_CLUSTER"
      value = var.frontend_cluster_name
    }

    environment_variable {
      name  = "ECS_SERVICE"
      value = var.backend_service_name
    }
  }

  source {
    type            = "GITHUB"
    location        = var.github_repo_url
    git_clone_depth = 1
    buildspec       = "backend/buildspec.yml"

    auth {
      type     = "SECRETS_MANAGER"
      resource = var.github_token_secret_arn
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/codebuild/${var.name_prefix}/backend"
      stream_name = "build"
    }
  }

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-backend-build"
    Service = "backend"
  })
}

############################################
# CloudWatch Log Groups for CodeBuild
############################################

resource "aws_cloudwatch_log_group" "frontend_build" {
  name              = "/codebuild/${var.name_prefix}/frontend"
  retention_in_days = 14

  tags = merge(var.tags, {
    Name    = "/codebuild/${var.name_prefix}/frontend"
    Service = "frontend"
  })
}

resource "aws_cloudwatch_log_group" "backend_build" {
  name              = "/codebuild/${var.name_prefix}/backend"
  retention_in_days = 14

  tags = merge(var.tags, {
    Name    = "/codebuild/${var.name_prefix}/backend"
    Service = "backend"
  })
}

############################################
# IAM — ECS Deploy Policy for CodeBuild
# Allows CodeBuild to trigger ECS rolling
# deploys after a successful image push.
############################################

resource "aws_iam_policy" "codebuild_ecs_deploy" {
  name        = "${var.name_prefix}-codebuild-ecs-deploy-policy"
  description = "Allows CodeBuild to update ECS services for rolling deploys."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "arn:aws:s3:::${var.artifacts_bucket_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::${var.artifacts_bucket_name}"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-codebuild-ecs-deploy-policy"
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_ecs_deploy" {
  role       = split("/", var.codebuild_role_arn)[1]
  policy_arn = aws_iam_policy.codebuild_ecs_deploy.arn
}

############################################
# CodeBuild Webhooks — Auto Build & Deploy
# Triggers on git pushes to the main branch
############################################

resource "aws_codebuild_webhook" "frontend" {
  project_name = aws_codebuild_project.frontend.name
  build_type   = "BUILD"

  # All filters in a group are ANDed: push to main AND a change under frontend/.
  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PUSH"
    }

    filter {
      type    = "HEAD_REF"
      pattern = "^refs/heads/main$"
    }

    filter {
      type    = "FILE_PATH"
      pattern = "^frontend/"
    }
  }
}

resource "aws_codebuild_webhook" "backend" {
  project_name = aws_codebuild_project.backend.name
  build_type   = "BUILD"

  # All filters in a group are ANDed: push to main AND a change under backend/.
  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PUSH"
    }

    filter {
      type    = "HEAD_REF"
      pattern = "^refs/heads/main$"
    }

    filter {
      type    = "FILE_PATH"
      pattern = "^backend/"
    }
  }
}
