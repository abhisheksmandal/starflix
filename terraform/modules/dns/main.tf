############################################
# Route 53 Hosted Zone
############################################

resource "aws_route53_zone" "this" {
  name = var.domain_name

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-zone"
  })
}

############################################
# ACM Certificate — ap-south-1 (ALB)
# Covers apex + wildcard.
# Attached to the ALB HTTPS listener.
############################################

resource "aws_acm_certificate" "alb" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  # Recreate before destroy to avoid ALB listener downtime during rotation.
  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-cert-alb"
  })
}

############################################
# ACM Certificate — us-east-1 (CloudFront)
# CloudFront is a global service whose control
# plane lives in us-east-1, so its certificate
# MUST be issued there — a regional (ap-south-1)
# cert is rejected by the distribution.
# Same names, validated via the same zone.
############################################

resource "aws_acm_certificate" "cloudfront" {
  provider = aws.us_east_1

  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-cert-cloudfront"
  })
}

############################################
# DNS Validation Records
# ACM issues the same validation CNAME for a
# given domain regardless of the cert's region,
# so both certs' options are merged and deduped
# by domain name — one Route 53 record validates
# both certificates. Keyed by domain_name (a
# static input) so for_each is known at plan time;
# the record name/value are apply-time values.
############################################

locals {
  validation_options = merge(
    {
      for dvo in aws_acm_certificate.alb.domain_validation_options :
      dvo.domain_name => {
        name   = dvo.resource_record_name
        type   = dvo.resource_record_type
        record = dvo.resource_record_value
      }
    },
    {
      for dvo in aws_acm_certificate.cloudfront.domain_validation_options :
      dvo.domain_name => {
        name   = dvo.resource_record_name
        type   = dvo.resource_record_type
        record = dvo.resource_record_value
      }
    }
  )
}

resource "aws_route53_record" "cert_validation" {
  for_each = local.validation_options

  zone_id = aws_route53_zone.this.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]

  allow_overwrite = true
}

############################################
# Certificate Validation
#
# NOTE: validation blocks until the CNAME
# resolves publicly, which requires this zone's
# name servers (zone_name_servers output) to be
# delegated at your registrar. On a brand-new
# domain, delegate first or this will time out.
############################################

resource "aws_acm_certificate_validation" "alb" {
  certificate_arn         = aws_acm_certificate.alb.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]

  timeouts {
    create = "60m"
  }
}

resource "aws_acm_certificate_validation" "cloudfront" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]

  timeouts {
    create = "60m"
  }
}
