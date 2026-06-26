############################################
# AWS VPC Endpoints
############################################
#
# Interface Endpoints
# -------------------
# • Amazon ECR (API)
# • Amazon ECR (Docker)
# • CloudWatch Logs
# • Secrets Manager
# • Systems Manager
# • EC2 Messages
# • SSM Messages
#
# Gateway Endpoint
# ----------------
# • Amazon S3
#
# All interface endpoints:
#   - Live in private subnets
#   - Use the endpoint security group
#   - Enable Private DNS
#
############################################

############################################
# Local values
############################################

locals {

  interface_endpoints = {
    ecr_api = {
      service = "com.amazonaws.${var.aws_region}.ecr.api"
    }

    ecr_dkr = {
      service = "com.amazonaws.${var.aws_region}.ecr.dkr"
    }

    logs = {
      service = "com.amazonaws.${var.aws_region}.logs"
    }

    secretsmanager = {
      service = "com.amazonaws.${var.aws_region}.secretsmanager"
    }

    ssm = {
      service = "com.amazonaws.${var.aws_region}.ssm"
    }

    ec2messages = {
      service = "com.amazonaws.${var.aws_region}.ec2messages"
    }

    ssmmessages = {
      service = "com.amazonaws.${var.aws_region}.ssmmessages"
    }
  }

}

############################################
# Interface Endpoints
############################################

resource "aws_vpc_endpoint" "interface" {

  for_each = local.interface_endpoints

  vpc_id = var.vpc_id

  service_name = each.value.service

  vpc_endpoint_type = "Interface"

  subnet_ids = var.private_subnet_ids

  security_group_ids = [
    var.endpoint_security_group_id
  ]

  private_dns_enabled = true

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-${each.key}-endpoint"
    }
  )
}

############################################
# S3 Gateway Endpoint
############################################

resource "aws_vpc_endpoint" "s3" {

  vpc_id = var.vpc_id

  service_name = "com.amazonaws.${var.aws_region}.s3"

  vpc_endpoint_type = "Gateway"

  route_table_ids = var.private_route_table_ids

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-s3-endpoint"
    }
  )
}