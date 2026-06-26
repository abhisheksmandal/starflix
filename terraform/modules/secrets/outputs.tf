# ── Secrets Manager ARNs ───────────────────────────────────────────────────────
# Pass these ARNs to ECS task definitions.
# The ECS agent resolves the actual secret value at container start.
# Plaintext values never appear in Terraform state.

output "tmdb_api_key_arn" {
  description = "ARN of the TMDB API key secret. Pass to backend ECS task definition."
  value       = aws_secretsmanager_secret.tmdb_api_key.arn
}

output "strapi_app_keys_arn" {
  description = "ARN of the Strapi APP_KEYS secret. Pass to backend ECS task definition."
  value       = aws_secretsmanager_secret.strapi_app_keys.arn
}

output "strapi_jwt_secret_arn" {
  description = "ARN of the Strapi JWT_SECRET. Pass to backend ECS task definition."
  value       = aws_secretsmanager_secret.strapi_jwt_secret.arn
}

output "strapi_api_token_salt_arn" {
  description = "ARN of the Strapi API_TOKEN_SALT secret. Pass to backend ECS task definition."
  value       = aws_secretsmanager_secret.strapi_api_token_salt.arn
}

output "strapi_admin_jwt_secret_arn" {
  description = "ARN of the Strapi ADMIN_JWT_SECRET. Pass to backend ECS task definition."
  value       = aws_secretsmanager_secret.strapi_admin_jwt_secret.arn
}

output "github_token_arn" {
  description = "ARN of the GitHub token secret. Pass to CodeBuild module."
  value       = aws_secretsmanager_secret.github_token.arn
}

# ── SSM Parameter ARNs ─────────────────────────────────────────────────────────

output "frontend_url_ssm_arn" {
  description = "ARN of the frontend URL SSM parameter. Null when frontend_url is not set."
  value       = length(aws_ssm_parameter.frontend_url) > 0 ? aws_ssm_parameter.frontend_url[0].arn : null
}

output "backend_url_ssm_arn" {
  description = "ARN of the backend URL SSM parameter. Null when backend_url is not set."
  value       = length(aws_ssm_parameter.backend_url) > 0 ? aws_ssm_parameter.backend_url[0].arn : null
}

# ── Secret Path Prefix ─────────────────────────────────────────────────────────

output "secret_path_prefix" {
  description = "Secrets Manager path prefix for this environment. Format: {project}/{environment}."
  value       = "${var.project}/${var.environment}"
}
