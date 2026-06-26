output "assets_bucket_name" {
  description = "Name of the S3 assets bucket (static media served via CloudFront)."
  value       = aws_s3_bucket.assets.id
}

output "assets_bucket_arn" {
  description = "ARN of the S3 assets bucket."
  value       = aws_s3_bucket.assets.arn
}

output "assets_bucket_domain_name" {
  description = "Regional domain name of the assets bucket. Used as CloudFront S3 origin."
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}

output "artifacts_bucket_name" {
  description = "Name of the S3 artifacts bucket (CodeBuild outputs)."
  value       = aws_s3_bucket.artifacts.id
}

output "artifacts_bucket_arn" {
  description = "ARN of the S3 artifacts bucket."
  value       = aws_s3_bucket.artifacts.arn
}
