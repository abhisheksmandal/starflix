terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

# ── S3 Bucket for Terraform State ─────────────────────────────────────────────
resource "aws_s3_bucket" "tfstate" {
  bucket        = local.bucket_name
  force_destroy = false

  tags = merge(var.tags, {
    Name = local.bucket_name
  })
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning to allow recovery from accidental state corruption
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable default server-side encryption using SSE-S3
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ── DynamoDB Table for Terraform State Locking ─────────────────────────────────
# Standard practice, though native S3 locking is also supported in TF 1.10+
resource "aws_dynamodb_table" "tfstate_locks" {
  name         = "${var.project}-tfstate-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge(var.tags, {
    Name = "${var.project}-tfstate-locks"
  })
}
