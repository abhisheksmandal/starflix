output "tfstate_bucket_name" {
  description = "Name of the S3 bucket created for Terraform remote state."
  value       = aws_s3_bucket.tfstate.id
}

output "tfstate_bucket_arn" {
  description = "ARN of the S3 bucket created for Terraform remote state."
  value       = aws_s3_bucket.tfstate.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table created for state locking."
  value       = aws_dynamodb_table.tfstate_locks.name
}
