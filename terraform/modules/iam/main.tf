############################################
# Assume Role Policies
############################################


data "aws_iam_policy_document" "ecs_task_assume" {

  statement {

    effect = "Allow"

    principals {

      type = "Service"

      identifiers = [
        "ecs-tasks.amazonaws.com"
      ]
    }

    actions = [
      "sts:AssumeRole"
    ]
  }
}


data "aws_iam_policy_document" "ecs_instance_assume" {

  statement {

    effect = "Allow"

    principals {

      type = "Service"

      identifiers = [
        "ec2.amazonaws.com"
      ]
    }

    actions = [
      "sts:AssumeRole"
    ]
  }
}


data "aws_iam_policy_document" "codebuild_assume" {

  statement {

    effect = "Allow"

    principals {

      type = "Service"

      identifiers = [
        "codebuild.amazonaws.com"
      ]
    }

    actions = [
      "sts:AssumeRole"
    ]
  }
}



############################################
# ECS Task Execution Role
############################################

resource "aws_iam_role" "ecs_task_execution" {

  name = "${var.name_prefix}-ecs-task-exec-role"

  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json


  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ecs-task-exec-role"
  })
}



resource "aws_iam_role_policy_attachment" "ecs_task_execution" {

  role = aws_iam_role.ecs_task_execution.name


  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}




############################################
# ECS Application Task Role
############################################


resource "aws_iam_role" "ecs_task" {

  name = "${var.name_prefix}-ecs-task-role"


  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json


  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ecs-task-role"
  })
}



data "aws_iam_policy_document" "ecs_task_policy" {


  statement {

    effect = "Allow"


    actions = [

      "ssm:GetParameter",
      "ssm:GetParameters",

      "secretsmanager:GetSecretValue"

    ]


    resources = [

      "*"

    ]
  }



  dynamic "statement" {

    for_each = var.assets_bucket_arn != "" ? [1] : []


    content {

      effect = "Allow"


      actions = [

        "s3:GetObject"

      ]


      resources = [

        "${var.assets_bucket_arn}/*"

      ]

    }
  }
}



resource "aws_iam_policy" "ecs_task_policy" {


  name = "${var.name_prefix}-ecs-task-policy"


  policy = data.aws_iam_policy_document.ecs_task_policy.json


  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ecs-task-policy"
  })
}



resource "aws_iam_role_policy_attachment" "ecs_task_policy" {


  role = aws_iam_role.ecs_task.name


  policy_arn = aws_iam_policy.ecs_task_policy.arn
}



############################################
# ECS EC2 Instance Role
############################################


resource "aws_iam_role" "ecs_instance" {


  name = "${var.name_prefix}-ecs-instance-role"


  assume_role_policy = data.aws_iam_policy_document.ecs_instance_assume.json


  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ecs-instance-role"
  })

}



resource "aws_iam_role_policy_attachment" "ecs_instance" {


  role = aws_iam_role.ecs_instance.name


  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"

}



resource "aws_iam_role_policy_attachment" "ecs_instance_ssm" {


  role = aws_iam_role.ecs_instance.name


  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

}



############################################
# CodeBuild Role
############################################


resource "aws_iam_role" "codebuild" {


  name = "${var.name_prefix}-codebuild-role"


  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json


  tags = merge(var.tags, {
    Name = "${var.name_prefix}-codebuild-role"
  })
}



data "aws_iam_policy_document" "codebuild_policy" {


  statement {

    effect = "Allow"


    actions = [

      "ecr:GetAuthorizationToken"

    ]


    resources = [
      "*"
    ]
  }



  statement {

    effect = "Allow"


    actions = [

      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart"

    ]


    resources = [
      "*"
    ]
  }



  statement {

    effect = "Allow"


    actions = [

      "logs:*"

    ]


    resources = [
      "*"
    ]
  }



  statement {

    effect = "Allow"


    actions = [

      "secretsmanager:GetSecretValue"

    ]


    resources = [
      var.github_token_secret_arn
    ]
  }

}



resource "aws_iam_policy" "codebuild" {


  name = "${var.name_prefix}-codebuild-policy"


  policy = data.aws_iam_policy_document.codebuild_policy.json


  tags = merge(var.tags, {
    Name = "${var.name_prefix}-codebuild-policy"
  })
}



resource "aws_iam_role_policy_attachment" "codebuild" {


  role = aws_iam_role.codebuild.name


  policy_arn = aws_iam_policy.codebuild.arn
}

############################################
# ECS Task Execution — Secrets Policy
# Allows ECS agent to fetch Secrets Manager
# and SSM values at container start time.
# Separate from the task role — this is the
# exec role used by the ECS agent itself.
############################################

data "aws_iam_policy_document" "ecs_task_exec_secrets" {
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "ssm:GetParameter",
      "ssm:GetParameters"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "ecs_task_exec_secrets" {
  name   = "${var.name_prefix}-ecs-task-exec-secrets-policy"
  policy = data.aws_iam_policy_document.ecs_task_exec_secrets.json

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ecs-task-exec-secrets-policy"
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec_secrets" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = aws_iam_policy.ecs_task_exec_secrets.arn
}
