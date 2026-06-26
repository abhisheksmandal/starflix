############################################
# Locals
############################################

locals {
  # Architecture naming convention:
  # {project}-{purpose}-{account_id}-{region}
  # name_prefix already carries {project}-{environment}; strip environment and
  # use project only for bucket names since they are globally unique and
  # environment is captured in the purpose segment via the name_prefix tag.
  # However, to keep environments isolated we include name_prefix in full so
  # that dev/stage/prod buckets never collide.
  assets_bucket_name    = "${var.name_prefix}-assets-${var.aws_account_id}-${var.aws_region}"
  artifacts_bucket_name = "${var.name_prefix}-artifacts-${var.aws_account_id}-${var.aws_region}"
}

############################################
# Assets Bucket
# Stores static media: posters, backdrops,
# thumbnails served via CloudFront OAC.
############################################

resource "aws_s3_bucket" "assets" {
  bucket        = local.assets_bucket_name
  force_destroy = var.assets_bucket_force_destroy

  tags = merge(var.tags, {
    Name    = local.assets_bucket_name
    Purpose = "assets"
  })
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }
  }
}

############################################
# Artifacts Bucket
# Stores CodeBuild build artifacts and
# packaged application zips.
############################################

resource "aws_s3_bucket" "artifacts" {
  bucket        = local.artifacts_bucket_name
  force_destroy = var.artifacts_bucket_force_destroy

  tags = merge(var.tags, {
    Name    = local.artifacts_bucket_name
    Purpose = "artifacts"
  })
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }
  }
}
