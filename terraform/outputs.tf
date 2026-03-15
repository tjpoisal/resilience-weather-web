output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (for cache invalidation)"
  value       = aws_cloudfront_distribution.main.id
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_database_name" {
  description = "RDS database name"
  value       = aws_db_instance.postgres.db_name
}

output "s3_static_bucket" {
  description = "S3 bucket for static assets"
  value       = aws_s3_bucket.static.id
}

output "ecr_repository_url" {
  description = "ECR repository URL for pushing Docker images"
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.app.name
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for ECS logs"
  value       = aws_cloudwatch_log_group.ecs.name
}

output "database_password_secret_arn" {
  description = "ARN of the database password in Secrets Manager"
  value       = aws_secretsmanager_secret.db_password.arn
}

output "session_secret_arn" {
  description = "ARN of the session secret in Secrets Manager"
  value       = aws_secretsmanager_secret.session_secret.arn
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "nat_gateway_ip" {
  description = "NAT Gateway public IP"
  value       = aws_eip.nat.public_ip
}

output "next_steps" {
  description = "Next steps for deployment"
  value       = <<-EOT
    1. Update your domain DNS records to point to CloudFront:
       CNAME resilienceweather.com → ${aws_cloudfront_distribution.main.domain_name}

    2. Push Docker image to ECR:
       aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.app.repository_url}
       docker build -t resilience-weather .
       docker tag resilience-weather:latest ${aws_ecr_repository.app.repository_url}:latest
       docker push ${aws_ecr_repository.app.repository_url}:latest

    3. Verify RDS is accessible and migrate schema (if applicable).

    4. Monitor ECS service and CloudWatch logs:
       https://console.aws.amazon.com/ecs/home?region=${var.aws_region}#/clusters/${aws_ecs_cluster.main.name}/services

    5. View audit logs in CloudTrail:
       https://console.aws.amazon.com/cloudtrail/

    6. Federal compliance: All infrastructure is audited via CloudTrail and encrypted with KMS keys.
  EOT
}
