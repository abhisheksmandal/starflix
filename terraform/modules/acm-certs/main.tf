############################################
# ACM Certificates — Frontend & Backend ALBs
# Two independent certificates (not one cert
# with two SANs) so each ALB's listener can be
# rotated/managed on its own.
#
# DNS is Cloudflare, not Route 53, so there is
# deliberately no aws_acm_certificate_validation
# resource here — that resource blocks `apply`
# until the validation CNAME resolves publicly.
# Instead, the validation records are exposed as
# outputs for the caller to add to Cloudflare by
# hand; the certificate ARNs are usable (attach
# them to a listener) immediately, they just won't
# complete a TLS handshake until ACM's side
# validates and flips the certificate to ISSUED.
############################################

resource "aws_acm_certificate" "frontend" {
  domain_name       = var.frontend_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-cert-frontend"
    Service = "frontend"
  })
}

resource "aws_acm_certificate" "backend" {
  domain_name       = var.backend_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-cert-backend"
    Service = "backend"
  })
}
