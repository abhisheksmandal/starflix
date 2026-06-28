# ── Frontend Repository ────────────────────────────────────────────────────────

resource "aws_ecr_repository" "frontend" {

  name = "${var.name_prefix}/frontend"

  force_delete = true

  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-frontend-ecr"
    Service = "frontend"
  })
}


# ── Backend Repository ─────────────────────────────────────────────────────────

resource "aws_ecr_repository" "backend" {

  name = "${var.name_prefix}/backend"

  force_delete = true

  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-backend-ecr"
    Service = "backend"
  })
}


# ── Lifecycle Policy ───────────────────────────────────────────────────────────
# Keeps latest 20 images.
# Removes old images automatically to reduce storage cost.

resource "aws_ecr_lifecycle_policy" "frontend" {

  repository = aws_ecr_repository.frontend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 20 frontend images"

        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 20
        }

        action = {
          type = "expire"
        }
      }
    ]
  })
}


resource "aws_ecr_lifecycle_policy" "backend" {

  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 20 backend images"

        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 20
        }

        action = {
          type = "expire"
        }
      }
    ]
  })
}
