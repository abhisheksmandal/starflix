output "zone_id" {
  description = "Route 53 hosted zone ID."
  value       = aws_route53_zone.this.zone_id
}

output "zone_name_servers" {
  description = "Name servers for the hosted zone. Delegate these at your registrar."
  value       = aws_route53_zone.this.name_servers
}

output "acm_certificate_arn" {
  description = "Validated ACM certificate ARN (ap-south-1). Attach to the ALB HTTPS listener."
  value       = aws_acm_certificate_validation.this.certificate_arn
}
