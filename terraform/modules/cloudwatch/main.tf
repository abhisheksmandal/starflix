############################################
# CloudWatch Dashboard
############################################

data "aws_region" "current" {}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "## ${var.name_prefix} — ECS + ALB Dashboard"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "ECS CPU Utilisation"
          region = data.aws_region.current.region
          period = 60
          stat   = "Average"
          view   = "timeSeries"
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.cluster_name, "ServiceName", var.frontend_service_name, { label = "Frontend CPU" }],
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.cluster_name, "ServiceName", var.backend_service_name, { label = "Backend CPU" }]
          ]
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "ECS Memory Utilisation"
          region = data.aws_region.current.region
          period = 60
          stat   = "Average"
          view   = "timeSeries"
          metrics = [
            ["AWS/ECS", "MemoryUtilization", "ClusterName", var.cluster_name, "ServiceName", var.frontend_service_name, { label = "Frontend Memory" }],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", var.cluster_name, "ServiceName", var.backend_service_name, { label = "Backend Memory" }]
          ]
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "ALB 5xx Errors"
          region = data.aws_region.current.region
          period = 60
          stat   = "Sum"
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.frontend_alb_arn_suffix, { label = "Frontend 5xx" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.backend_alb_arn_suffix, { label = "Backend 5xx" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "ALB Target Response Time (s)"
          region = data.aws_region.current.region
          period = 60
          stat   = "Average"
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.frontend_alb_arn_suffix, { label = "Frontend" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.backend_alb_arn_suffix, { label = "Backend" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "ALB Request Count"
          region = data.aws_region.current.region
          period = 60
          stat   = "Sum"
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.frontend_alb_arn_suffix, { label = "Frontend Requests" }],
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.backend_alb_arn_suffix, { label = "Backend Requests" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "ALB Healthy Host Count"
          region = data.aws_region.current.region
          period = 60
          stat   = "Average"
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", var.frontend_alb_arn_suffix, "TargetGroup", var.frontend_tg_arn_suffix, { label = "Frontend Healthy" }],
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", var.backend_alb_arn_suffix, "TargetGroup", var.backend_tg_arn_suffix, { label = "Backend Healthy" }]
          ]
        }
      }
    ]
  })
}

############################################
# Alarms — ECS CPU
############################################

resource "aws_cloudwatch_metric_alarm" "frontend_cpu" {
  alarm_name          = "${var.name_prefix}-frontend-cpu-high"
  alarm_description   = "Frontend ECS CPU utilisation exceeded ${var.cpu_threshold}%."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.cpu_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.frontend_service_name
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-frontend-cpu-high"
    Service = "frontend"
  })
}

resource "aws_cloudwatch_metric_alarm" "backend_cpu" {
  alarm_name          = "${var.name_prefix}-backend-cpu-high"
  alarm_description   = "Backend ECS CPU utilisation exceeded ${var.cpu_threshold}%."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.cpu_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.backend_service_name
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-backend-cpu-high"
    Service = "backend"
  })
}

############################################
# Alarms — ECS Memory
############################################

resource "aws_cloudwatch_metric_alarm" "frontend_memory" {
  alarm_name          = "${var.name_prefix}-frontend-memory-high"
  alarm_description   = "Frontend ECS memory utilisation exceeded ${var.memory_threshold}%."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.memory_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.frontend_service_name
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-frontend-memory-high"
    Service = "frontend"
  })
}

resource "aws_cloudwatch_metric_alarm" "backend_memory" {
  alarm_name          = "${var.name_prefix}-backend-memory-high"
  alarm_description   = "Backend ECS memory utilisation exceeded ${var.memory_threshold}%."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.memory_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.backend_service_name
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-backend-memory-high"
    Service = "backend"
  })
}

############################################
# Alarms — ALB 5xx Errors
############################################

resource "aws_cloudwatch_metric_alarm" "frontend_5xx" {
  alarm_name          = "${var.name_prefix}-frontend-5xx-high"
  alarm_description   = "Frontend ALB 5xx errors exceeded ${var.alb_5xx_threshold} per minute."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = var.alb_5xx_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.frontend_alb_arn_suffix
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-frontend-5xx-high"
    Service = "frontend"
  })
}

resource "aws_cloudwatch_metric_alarm" "backend_5xx" {
  alarm_name          = "${var.name_prefix}-backend-5xx-high"
  alarm_description   = "Backend ALB 5xx errors exceeded ${var.alb_5xx_threshold} per minute."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = var.alb_5xx_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.backend_alb_arn_suffix
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-backend-5xx-high"
    Service = "backend"
  })
}

############################################
# Alarms — ALB Response Time
############################################

resource "aws_cloudwatch_metric_alarm" "frontend_response_time" {
  alarm_name          = "${var.name_prefix}-frontend-response-time-high"
  alarm_description   = "Frontend ALB response time exceeded ${var.alb_response_time_threshold}s."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = var.alb_response_time_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.frontend_alb_arn_suffix
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-frontend-response-time-high"
    Service = "frontend"
  })
}

resource "aws_cloudwatch_metric_alarm" "backend_response_time" {
  alarm_name          = "${var.name_prefix}-backend-response-time-high"
  alarm_description   = "Backend ALB response time exceeded ${var.alb_response_time_threshold}s."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = var.alb_response_time_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.backend_alb_arn_suffix
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-backend-response-time-high"
    Service = "backend"
  })
}
