############################################
# ECS Cluster
############################################

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-cluster"
  })
}

############################################
# ECS Cluster Capacity Provider
# Ties the ASG to the ECS cluster so ECS
# can scale EC2 instances automatically.
############################################

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = [aws_ecs_capacity_provider.this.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    base              = 1
    weight            = 100
  }
}

resource "aws_ecs_capacity_provider" "this" {
  name = "${var.name_prefix}-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.this.arn

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 80
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 5
    }

    managed_termination_protection = "DISABLED"
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-capacity-provider"
  })
}

############################################
# IAM Instance Profile
# Wraps the existing ECS instance role so
# it can be attached to EC2 instances.
############################################

resource "aws_iam_instance_profile" "ecs" {
  name = "${var.name_prefix}-ecs-instance-profile"
  role = var.ecs_instance_role_name

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ecs-instance-profile"
  })
}

############################################
# AMI Selection
# Uses custom AMI if provided, otherwise
# falls back to latest ECS-optimised
# Amazon Linux 2 AMI from SSM.
############################################

data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ssm_parameter.ecs_ami.value
}

############################################
# EC2 Launch Template
# Defines the configuration for ECS host
# instances — AMI, instance type, storage,
# user data to register with the cluster.
############################################

resource "aws_launch_template" "ecs" {
  name        = "${var.name_prefix}-lt"
  description = "Launch template for ECS EC2 hosts in the ${var.name_prefix} cluster."

  image_id      = local.ami_id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs.name
  }

  vpc_security_group_ids = [var.ecs_security_group_id]

  # Register instance with the ECS cluster on boot.
  user_data = base64encode(<<-EOT
    #!/bin/bash
    mkdir -p /etc/ecs
    echo ECS_CLUSTER=${aws_ecs_cluster.this.name} >> /etc/ecs/ecs.config
    echo ECS_ENABLE_CONTAINER_METADATA=true >> /etc/ecs/ecs.config
  EOT
  )

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.root_volume_size_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(var.tags, {
      Name        = "${var.name_prefix}-ecs-host"
      AutoScaling = "true"
    })
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(var.tags, {
      Name = "${var.name_prefix}-ecs-host-volume"
    })
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-lt"
  })
}

############################################
# Auto Scaling Group
# Manages EC2 instance lifecycle across
# private subnets. ECS capacity provider
# drives scaling based on cluster load.
############################################

resource "aws_autoscaling_group" "this" {
  name = "${var.name_prefix}-asg"

  desired_capacity = var.desired_capacity
  min_size         = var.min_size
  max_size         = var.max_size

  force_delete = true

  vpc_zone_identifier = var.private_subnet_ids

  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }

  # Allow ECS capacity provider to manage instance termination.
  protect_from_scale_in = false

  # Health check — EC2 default; ECS manages task-level health separately.
  health_check_type         = "EC2"
  health_check_grace_period = 120

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-ecs-host"
    propagate_at_launch = true
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}
