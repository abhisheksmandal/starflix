output "frontend_certificate_arn" {
  description = "ARN of the frontend ACM certificate. Attach to the frontend ALB HTTPS listener. Usable immediately, but TLS handshakes only succeed once ACM validation completes."
  value       = aws_acm_certificate.frontend.arn
}

output "backend_certificate_arn" {
  description = "ARN of the backend ACM certificate. Attach to the backend ALB HTTPS listener. Usable immediately, but TLS handshakes only succeed once ACM validation completes."
  value       = aws_acm_certificate.backend.arn
}

output "validation_records" {
  description = "DNS validation records to add in Cloudflare (type CNAME, proxy status DNS-only) for both certificates to move from PENDING_VALIDATION to ISSUED."
  value = merge(
    {
      for dvo in aws_acm_certificate.frontend.domain_validation_options :
      dvo.domain_name => {
        name  = dvo.resource_record_name
        type  = dvo.resource_record_type
        value = dvo.resource_record_value
      }
    },
    {
      for dvo in aws_acm_certificate.backend.domain_validation_options :
      dvo.domain_name => {
        name  = dvo.resource_record_name
        type  = dvo.resource_record_type
        value = dvo.resource_record_value
      }
    }
  )
}
