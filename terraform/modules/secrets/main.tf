############################################
# Locals
############################################

locals {
  # Secrets Manager path convention: {project}/{environment}/{name}
  secret_path = "${var.project}/${var.environment}"

  # SSM Parameter path convention: /{project}/{environment}/{name}
  ssm_path = "/${var.project}/${var.environment}"
}

############################################
# TMDB API Key
# Used by Strapi backend to fetch movie
# metadata from The Movie Database API.
# Value set out-of-band via AWS console
# or CI secret injection — never in state.
############################################

resource "aws_secretsmanager_secret" "tmdb_api_key" {
  name                    = "${local.secret_path}/tmdb-api-key"
  description             = "TMDB API key for fetching movie metadata. Set value out-of-band."
  recovery_window_in_days = var.recovery_window_days

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-tmdb-api-key"
    Service = "backend"
  })
}

############################################
# Strapi App Keys
# Comma-separated list of secrets used by
# Strapi for session signing.
############################################

resource "aws_secretsmanager_secret" "strapi_app_keys" {
  name                    = "${local.secret_path}/strapi-app-keys"
  description             = "Strapi APP_KEYS — comma-separated signing secrets. Set value out-of-band."
  recovery_window_in_days = var.recovery_window_days

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-strapi-app-keys"
    Service = "backend"
  })
}

############################################
# Strapi JWT Secret
# Used to sign user-facing JWTs issued
# by the Strapi Users & Permissions plugin.
############################################

resource "aws_secretsmanager_secret" "strapi_jwt_secret" {
  name                    = "${local.secret_path}/strapi-jwt-secret"
  description             = "Strapi JWT_SECRET for user token signing. Set value out-of-band."
  recovery_window_in_days = var.recovery_window_days

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-strapi-jwt-secret"
    Service = "backend"
  })
}

############################################
# Strapi API Token Salt
# Used to hash API tokens generated in
# the Strapi admin panel.
############################################

resource "aws_secretsmanager_secret" "strapi_api_token_salt" {
  name                    = "${local.secret_path}/strapi-api-token-salt"
  description             = "Strapi API_TOKEN_SALT for hashing API tokens. Set value out-of-band."
  recovery_window_in_days = var.recovery_window_days

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-strapi-api-token-salt"
    Service = "backend"
  })
}

############################################
# Strapi Admin JWT Secret
# Used to sign admin panel JWTs — separate
# from user JWTs for least-privilege.
############################################

resource "aws_secretsmanager_secret" "strapi_admin_jwt_secret" {
  name                    = "${local.secret_path}/strapi-admin-jwt-secret"
  description             = "Strapi ADMIN_JWT_SECRET for admin panel token signing. Set value out-of-band."
  recovery_window_in_days = var.recovery_window_days

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-strapi-admin-jwt-secret"
    Service = "backend"
  })
}

############################################
# GitHub Token
# Used by CodeBuild to pull source code
# from the GitHub repository.
# Value set out-of-band — never in state.
############################################

resource "aws_secretsmanager_secret" "github_token" {
  name                    = "${local.secret_path}/github-token"
  description             = "GitHub personal access token for CodeBuild source pull. Set value out-of-band."
  recovery_window_in_days = var.recovery_window_days

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-github-token"
    Service = "codebuild"
  })
}

############################################
# SSM Parameters — Non-sensitive config
# Stored as String type; not secret enough
# for Secrets Manager.
# Created only when values are provided —
# wired in after CloudFront URLs are known.
############################################

resource "aws_ssm_parameter" "frontend_url" {
  count = var.frontend_url != "" ? 1 : 0

  name        = "${local.ssm_path}/frontend-url"
  description = "Public URL of the Node.js frontend. Injected into backend container as FRONTEND_URL."
  type        = "String"
  value       = var.frontend_url

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-frontend-url"
    Service = "frontend"
  })
}

resource "aws_ssm_parameter" "backend_url" {
  count = var.backend_url != "" ? 1 : 0

  name        = "${local.ssm_path}/backend-url"
  description = "Public URL of the Strapi backend API. Injected into frontend container as BACKEND_URL."
  type        = "String"
  value       = var.backend_url

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-backend-url"
    Service = "backend"
  })
}
