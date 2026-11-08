output "repository_urls" {
  description = "Map of ECR repository names to their repository URLs"
  value = {
    for idx, repo in aws_ecr_repository.repos :
    var.repository_names[idx] => repo.repository_url
  }
}

output "repository_arns" {
  description = "List of ARNs of the created ECR repositories"
  value       = aws_ecr_repository.repos[*].arn
}

