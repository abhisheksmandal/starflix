output "dashboard_name" {
  description = "Name of the CloudWatch dashboard."
  value       = aws_cloudwatch_dashboard.this.dashboard_name
}

output "dashboard_url" {
  description = "URL of the CloudWatch dashboard."
  value       = "https://console.aws.amazon.com/cloudwatch/home#dashboards:name=${aws_cloudwatch_dashboard.this.dashboard_name}"
}

output "frontend_cpu_alarm_arn" {
  description = "ARN of the frontend CPU alarm."
  value       = aws_cloudwatch_metric_alarm.frontend_cpu.arn
}

output "backend_cpu_alarm_arn" {
  description = "ARN of the backend CPU alarm."
  value       = aws_cloudwatch_metric_alarm.backend_cpu.arn
}

output "frontend_memory_alarm_arn" {
  description = "ARN of the frontend memory alarm."
  value       = aws_cloudwatch_metric_alarm.frontend_memory.arn
}

output "backend_memory_alarm_arn" {
  description = "ARN of the backend memory alarm."
  value       = aws_cloudwatch_metric_alarm.backend_memory.arn
}

output "frontend_5xx_alarm_arn" {
  description = "ARN of the frontend 5xx alarm."
  value       = aws_cloudwatch_metric_alarm.frontend_5xx.arn
}

output "backend_5xx_alarm_arn" {
  description = "ARN of the backend 5xx alarm."
  value       = aws_cloudwatch_metric_alarm.backend_5xx.arn
}
