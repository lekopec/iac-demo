output "ecr_url" {
  description = "ecr repo url"
  value = aws_ecr_repository.demo_repo.repository_url
}
