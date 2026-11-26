# ==============================================================================
# ShopLite: Amazon ECR Module (Question 4.e)
# - ECR repositories for all 3 microservices (web, catalog-api, order-worker)
# - Scan on push enabled for automated DevSecOps vulnerability checks
# - Image lifecycle policy for cost optimization
# ==============================================================================

resource "aws_ecr_repository" "repos" {
  count                = length(var.repository_names)
  name                 = var.repository_names[count.index]
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = var.repository_names[count.index]
  }
}

# Cost Guard: Lifecycle policy to retain only the last 15 images
resource "aws_ecr_lifecycle_policy" "cleanup_policy" {
  count      = length(var.repository_names)
  repository = aws_ecr_repository.repos[count.index].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Retain last 15 images to avoid billing accumulation"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 15
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

