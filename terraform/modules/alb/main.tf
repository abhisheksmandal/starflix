############################################
# Frontend ALB
# Public-facing; serves React/nginx on
# port 80 (redirect) and 443 (HTTPS).
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

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-tg-frontend"
    Service = "frontend"
  })
}

# ── Frontend HTTP Listener — redirect to HTTPS ─────────────────────────────────

resource "aws_lb_listener" "frontend_http" {
  load_balancer_arn = aws_lb.frontend.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
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
  count = var.acm_certificate_arn != null ? 1 : 0

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
# Public-facing; serves Express API on
# port 4000 directly from the internet.
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
# Internal ALB uses HTTP only — traffic stays within the VPC security boundary.

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
