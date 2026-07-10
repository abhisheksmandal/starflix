############################################
# Frontend ALB
# Public-facing; serves Node.js frontend.
# When acm_certificate_arn is null (dev):
#   port 80 → forward to target group
# When acm_certificate_arn is set (prod):
#   port 80 → 301 redirect to HTTPS
#   port 443 → forward to target group
############################################

resource "aws_lb" "frontend" {
  name               = "${var.name_prefix}-alb-frontend"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-alb-frontend"
    Service = "frontend"
  })
}

# ── Frontend Target Group ──────────────────────────────────────────────────────

resource "aws_lb_target_group" "frontend" {
  name        = "${var.name_prefix}-tg-frontend"
  port        = var.frontend_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = var.health_check_path_frontend
    protocol            = "HTTP"
    matcher             = "200-299"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 30

  # Pins a browser to one task version for the life of its session so a single
  # page load can't fetch index.html from a new task and a content-hashed JS
  # chunk from an old (or vice versa) during a rolling deploy, which 404s and
  # leaves a blank page. Duration only needs to outlast one rollout window.
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 3600
    enabled         = true
  }

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-tg-frontend"
    Service = "frontend"
  })
}

# ── Frontend HTTP Listener ─────────────────────────────────────────────────────
# When no cert: forward directly to target group (dev).
# When cert present: redirect to HTTPS (stage/prod).

resource "aws_lb_listener" "frontend_http" {
  load_balancer_arn = aws_lb.frontend.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.enable_https ? [] : [1]
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.frontend.arn
    }
  }

  dynamic "default_action" {
    for_each = var.enable_https ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-frontend-http-listener"
    Service = "frontend"
  })
}

# ── Frontend HTTPS Listener ────────────────────────────────────────────────────
# Only created when an ACM certificate ARN is provided.

resource "aws_lb_listener" "frontend_https" {
  count = var.enable_https ? 1 : 0

  load_balancer_arn = aws_lb.frontend.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-frontend-https-listener"
    Service = "frontend"
  })
}

############################################
# Backend ALB
# Internal-facing; serves Strapi API.
# HTTP only — CloudFront terminates TLS.
############################################

resource "aws_lb" "backend" {
  name               = "${var.name_prefix}-alb-backend"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-alb-backend"
    Service = "backend"
  })
}

# ── Backend Target Group ───────────────────────────────────────────────────────

resource "aws_lb_target_group" "backend" {
  name        = "${var.name_prefix}-tg-backend"
  port        = var.backend_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = var.health_check_path_backend
    protocol            = "HTTP"
    matcher             = "200-299"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 30

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-tg-backend"
    Service = "backend"
  })
}

# ── Backend HTTP Listener ──────────────────────────────────────────────────────
# Left forwarding (not redirected) even when HTTPS is enabled, so the plain
# :backend_port endpoint keeps working for anything not yet migrated to HTTPS.

resource "aws_lb_listener" "backend_http" {
  load_balancer_arn = aws_lb.backend.arn
  port              = var.backend_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-backend-http-listener"
    Service = "backend"
  })
}

# ── Backend HTTPS Listener ─────────────────────────────────────────────────────
# Only created when an ACM certificate ARN is provided. Terminates TLS on 443
# and forwards plaintext to the same target group (container still listens on
# backend_port internally) — no ECS/task changes needed to expose 443.

resource "aws_lb_listener" "backend_https" {
  count = var.enable_https ? 1 : 0

  load_balancer_arn = aws_lb.backend.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.backend_acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-backend-https-listener"
    Service = "backend"
  })
}
