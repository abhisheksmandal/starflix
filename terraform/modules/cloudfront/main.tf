############################################
# CloudFront Origin Access Control (OAC)
# Grants CloudFront exclusive access to the
# S3 assets bucket. No public S3 access.
############################################

resource "aws_cloudfront_origin_access_control" "assets" {
  name                              = "${var.name_prefix}-oac"
  description                       = "OAC for ${var.name_prefix} S3 assets bucket."
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

############################################
# S3 Bucket Policy
# Allows GetObject from this CloudFront
# distribution only — no public access.
############################################

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_policy" "assets" {
  bucket = var.assets_bucket_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::${var.assets_bucket_name}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.this.arn
          }
        }
      }
    ]
  })
}

############################################
# Cache Policies
############################################

# Frontend — light caching for HTML pages.
resource "aws_cloudfront_cache_policy" "frontend" {
  name        = "${var.name_prefix}-frontend-cache-policy"
  comment     = "Light caching for Node.js frontend HTML responses."
  default_ttl = 60
  min_ttl     = 0
  max_ttl     = 300

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }

    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

# Backend API — no caching.
# TTL = 0 so nothing is cached.
# Headers/cookies/QS forwarded via origin request policy below.
resource "aws_cloudfront_cache_policy" "backend" {
  name        = "${var.name_prefix}-backend-cache-policy"
  comment     = "No caching for Strapi API responses."
  default_ttl = 0
  min_ttl     = 0
  max_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }

    enable_accept_encoding_gzip   = false
    enable_accept_encoding_brotli = false
  }
}

# Static assets — aggressive caching.
resource "aws_cloudfront_cache_policy" "static_assets" {
  name        = "${var.name_prefix}-static-cache-policy"
  comment     = "Aggressive caching for S3 static assets (posters, backdrops)."
  default_ttl = 86400
  min_ttl     = 86400
  max_ttl     = 31536000

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }

    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

############################################
# Origin Request Policy — Backend
# Forwards all headers, cookies and query
# strings to Strapi. Separate from the
# cache policy since cache policy only
# controls what goes into the cache key.
############################################

resource "aws_cloudfront_origin_request_policy" "backend" {
  name    = "${var.name_prefix}-backend-origin-request-policy"
  comment = "Forward all headers, cookies and query strings to Strapi backend."

  cookies_config {
    cookie_behavior = "all"
  }

  headers_config {
    header_behavior = "allViewer"
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

############################################
# CloudFront Distribution
############################################

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.name_prefix}-cdn"
  price_class         = var.price_class
  wait_for_deployment = false

  aliases = var.acm_certificate_arn != null ? [
    var.domain_name,
    "www.${var.domain_name}",
    "api.${var.domain_name}"
  ] : []

  # ── Origin 1: Frontend ALB ─────────────────────────────────────────────────

  origin {
    origin_id   = "origin-frontend"
    domain_name = var.frontend_alb_dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Forwarded-Host"
      value = var.domain_name
    }
  }

  # ── Origin 2: Backend ALB ──────────────────────────────────────────────────

  origin {
    origin_id   = "origin-backend"
    domain_name = var.backend_alb_dns_name

    custom_origin_config {
      http_port              = var.backend_port
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Forwarded-Host"
      value = "api.${var.domain_name}"
    }
  }

  # ── Origin 3: S3 Assets ────────────────────────────────────────────────────

  origin {
    origin_id                = "origin-s3"
    domain_name              = var.assets_bucket_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.assets.id
  }

  # ── Behaviour 1: Static Assets → S3 ───────────────────────────────────────

  ordered_cache_behavior {
    path_pattern           = "/static/*"
    target_origin_id       = "origin-s3"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = aws_cloudfront_cache_policy.static_assets.id
    compress               = true

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]
  }

  # ── Behaviour 2: API → Backend ALB ────────────────────────────────────────

  ordered_cache_behavior {
    path_pattern              = "/api/*"
    target_origin_id          = "origin-backend"
    viewer_protocol_policy    = "redirect-to-https"
    cache_policy_id           = aws_cloudfront_cache_policy.backend.id
    origin_request_policy_id  = aws_cloudfront_origin_request_policy.backend.id
    compress                  = false

    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]
  }

  # ── Default Behaviour: Frontend ALB ───────────────────────────────────────

  default_cache_behavior {
    target_origin_id       = "origin-frontend"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = aws_cloudfront_cache_policy.frontend.id
    compress               = true

    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]
  }

  # ── TLS ────────────────────────────────────────────────────────────────────

  viewer_certificate {
    acm_certificate_arn            = var.acm_certificate_arn
    ssl_support_method             = var.acm_certificate_arn != null ? "sni-only" : null
    minimum_protocol_version       = var.acm_certificate_arn != null ? "TLSv1.2_2021" : null
    cloudfront_default_certificate = var.acm_certificate_arn == null ? true : false
  }

  # ── WAF ────────────────────────────────────────────────────────────────────

  web_acl_id = var.enable_waf ? var.waf_acl_arn : null

  # ── Geo Restriction ────────────────────────────────────────────────────────

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-cdn"
  })

  depends_on = [aws_cloudfront_origin_access_control.assets]
}
