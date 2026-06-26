# AWS provider 6.x removed inline ingress/egress blocks from aws_security_group.
# All rules are managed as separate aws_vpc_security_group_ingress_rule /
# aws_vpc_security_group_egress_rule resources.
#
# Dependency note: ALB SG egress rules reference the ECS SG, and ECS SG ingress
# rules reference the ALB SG. With separate rule resources (vs inline blocks)
# Terraform resolves this correctly - both SGs are created first, then the rules.

# ── ALB Security Group ─────────────────────────────────────────────────────────
# Accepts inbound HTTPS (and HTTP for redirect) from the public internet.
# Sends outbound only to ECS tasks on the exact container ports.

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Controls inbound internet traffic to the Application Load Balancer."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-alb-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet - ALB listener rule redirects to HTTPS"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs_frontend" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Outbound to ECS frontend tasks on container port"
  ip_protocol                  = "tcp"
  from_port                    = var.frontend_port
  to_port                      = var.frontend_port
  referenced_security_group_id = aws_security_group.ecs.id
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs_backend" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Outbound to ECS backend tasks on container port"
  ip_protocol                  = "tcp"
  from_port                    = var.backend_port
  to_port                      = var.backend_port
  referenced_security_group_id = aws_security_group.ecs.id
}

# ── ECS Security Group ─────────────────────────────────────────────────────────
# Accepts inbound only from the ALB on the known container ports.
# Sends outbound HTTPS to reach AWS APIs (via VPC endpoints or NAT Gateway)
# and the public internet for external calls (TMDB API etc.).

resource "aws_security_group" "ecs" {
  name        = "${var.name_prefix}-ecs-sg"
  description = "Controls traffic to and from ECS task ENIs."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ecs-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb_frontend" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Frontend container port inbound from ALB"
  ip_protocol                  = "tcp"
  from_port                    = var.frontend_port
  to_port                      = var.frontend_port
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb_backend" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Backend container port inbound from ALB"
  ip_protocol                  = "tcp"
  from_port                    = var.backend_port
  to_port                      = var.backend_port
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "ecs_https_out" {
  security_group_id = aws_security_group.ecs.id
  description       = "HTTPS outbound - covers AWS VPC endpoints and internet via NAT Gateway"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# ── VPC Endpoint Security Group ────────────────────────────────────────────────
# Attached to interface endpoints (ECR, SSM, Secrets Manager, CloudWatch Logs).
# Accepts inbound HTTPS from ECS tasks only - no other source, no egress needed.

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.name_prefix}-endpoint-sg"
  description = "Controls access to VPC interface endpoints. Accepts HTTPS from ECS tasks only."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-endpoint-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "endpoint_from_ecs" {
  security_group_id            = aws_security_group.vpc_endpoints.id
  description                  = "HTTPS from ECS tasks to AWS interface endpoints"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.ecs.id
}
