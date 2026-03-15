# Resilience Weather AWS Infrastructure
# Terraform configuration for production deployment
# Provisions: ECS Fargate, RDS PostgreSQL, ALB, CloudFront, Secrets Manager, CloudTrail

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Store state in S3 for team collaboration (optional, but recommended)
  # Uncomment after first apply with local state
  # backend "s3" {
  #   bucket         = "resilience-weather-terraform-state"
  #   key            = "prod/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project             = "Resilience Weather"
      Environment         = var.environment
      ManagedBy           = "Terraform"
      Organization        = "Get Stack MAX LLC"
      FederalCompliance   = "true"
      GrantApplicant      = "NOAA-NWS-2024-28059"
      AuditTrailEnabled   = "true"
    }
  }
}

# ──────────────────────────────────────
# DATA SOURCES
# ──────────────────────────────────────

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# ──────────────────────────────────────
# SECURITY GROUPS
# ──────────────────────────────────────

resource "aws_security_group" "alb" {
  name        = "resilience-alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "resilience-alb-sg"
  }
}

resource "aws_security_group" "ecs" {
  name        = "resilience-ecs-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "resilience-ecs-sg"
  }
}

resource "aws_security_group" "rds" {
  name        = "resilience-rds-sg"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "resilience-rds-sg"
  }
}

# ──────────────────────────────────────
# NETWORKING
# ──────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "resilience-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "resilience-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "resilience-public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count              = 2
  vpc_id             = aws_vpc.main.id
  cidr_block         = var.private_subnets[count.index]
  availability_zone  = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "resilience-private-subnet-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block      = "0.0.0.0/0"
    gateway_id      = aws_internet_gateway.main.id
  }

  tags = {
    Name = "resilience-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway for private subnets to access internet
resource "aws_eip" "nat" {
  domain = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "resilience-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "resilience-nat"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "resilience-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ──────────────────────────────────────
# RDS POSTGRESQL
# ──────────────────────────────────────

resource "aws_db_subnet_group" "main" {
  name       = "resilience-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "resilience-db-subnet-group"
  }
}

resource "aws_db_instance" "postgres" {
  identifier              = "resilience-db"
  allocated_storage       = var.db_allocated_storage
  storage_type            = "gp3"
  engine                  = "postgres"
  engine_version          = "16.0"
  instance_class          = var.db_instance_class
  db_name                 = "resilience_db"
  username                = "resilience_admin"
  password                = random_password.db_password.result
  parameter_group_name    = aws_db_parameter_group.postgres.name
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  
  # Compliance: automated backups, encryption, multi-AZ
  backup_retention_period = 30
  backup_window          = "03:00-04:00"
  maintenance_window     = "mon:04:00-mon:05:00"
  multi_az               = true
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.rds.arn
  
  # Performance
  performance_insights_enabled    = true
  performance_insights_retention_period = 7
  enable_cloudwatch_logs_exports = ["postgresql"]
  
  # Compliance: deletion protection
  deletion_protection = true
  skip_final_snapshot = false
  final_snapshot_identifier = "resilience-db-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  
  depends_on = [aws_security_group.rds]

  tags = {
    Name = "resilience-postgres"
  }
}

resource "aws_db_parameter_group" "postgres" {
  family = "postgres16"
  name   = "resilience-postgres-params"

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = {
    Name = "resilience-postgres-params"
  }
}

resource "random_password" "db_password" {
  length  = 32
  special = true
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "resilience/database/password"
  recovery_window_in_days = 7

  tags = {
    Name = "resilience-db-password"
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = aws_db_instance.postgres.username
    password = random_password.db_password.result
    engine   = "postgres"
    host     = aws_db_instance.postgres.endpoint
    port     = 5432
    dbname   = aws_db_instance.postgres.db_name
  })
}

# ──────────────────────────────────────
# KMS ENCRYPTION KEYS
# ──────────────────────────────────────

resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS encryption (Resilience Weather)"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name = "resilience-rds-key"
  }
}

resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 encryption (Resilience Weather)"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name = "resilience-s3-key"
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/resilience-rds"
  target_key_id = aws_kms_key.rds.key_id
}

resource "aws_kms_alias" "s3" {
  name          = "alias/resilience-s3"
  target_key_id = aws_kms_key.s3.key_id
}

# ──────────────────────────────────────
# S3 BUCKETS (STATIC ASSETS, APK DISTRIBUTION)
# ──────────────────────────────────────

resource "aws_s3_bucket" "static" {
  bucket = "resilience-weather-static-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "resilience-static-assets"
  }
}

resource "aws_s3_bucket_versioning" "static" {
  bucket = aws_s3_bucket.static.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "static" {
  bucket = aws_s3_bucket.static.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "static" {
  bucket = aws_s3_bucket.static.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "static_cloudfront" {
  bucket = aws_s3_bucket.static.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontAccess"
      Effect = "Allow"
      Principal = {
        Service = "cloudfront.amazonaws.com"
      }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.static.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
        }
      }
    }]
  })
}

# ──────────────────────────────────────
# ECR (ELASTIC CONTAINER REGISTRY)
# ──────────────────────────────────────

resource "aws_ecr_repository" "app" {
  name                 = "resilience-weather"
  image_tag_mutability = "IMMUTABLE"
  
  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.s3.arn
  }

  tags = {
    Name = "resilience-weather-app"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus     = "any"
        countType     = "imageCountMoreThan"
        countNumber   = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# ──────────────────────────────────────
# LOAD BALANCER (ALB)
# ──────────────────────────────────────

resource "aws_lb" "main" {
  name               = "resilience-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false
  enable_http2              = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "resilience-alb"
  }
}

resource "aws_lb_target_group" "app" {
  name        = "resilience-app-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
  }

  tags = {
    Name = "resilience-app-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS listener (certificate managed separately or via ACM)
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ──────────────────────────────────────
# ECS CLUSTER & SERVICE
# ──────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = "resilience-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "resilience-cluster"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "resilience-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name      = "resilience-app"
    image     = "${aws_ecr_repository.app.repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = 3000
      hostPort      = 3000
      protocol      = "tcp"
    }]

    environment = [
      {
        name  = "NODE_ENV"
        value = var.environment
      },
      {
        name  = "PORT"
        value = "3000"
      },
      {
        name  = "NOAA_BASE_URL"
        value = "https://api.weather.gov"
      }
    ]

    secrets = [
      {
        name      = "SESSION_SECRET"
        valueFrom = "${aws_secretsmanager_secret.session_secret.arn}:SESSION_SECRET::"
      },
      {
        name      = "DATABASE_URL"
        valueFrom = "${aws_secretsmanager_secret.db_connection.arn}:DATABASE_URL::"
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = {
    Name = "resilience-app-task"
  }
}

resource "aws_ecs_service" "app" {
  name            = "resilience-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "resilience-app"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.https]

  tags = {
    Name = "resilience-service"
  }
}

# Auto-scaling
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = var.ecs_max_capacity
  min_capacity       = var.ecs_desired_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_cpu" {
  name               = "resilience-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

resource "aws_appautoscaling_policy" "ecs_memory" {
  name               = "resilience-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value = 80.0
  }
}

# ──────────────────────────────────────
# CLOUDFRONT (CDN)
# ──────────────────────────────────────

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  http_version        = "http2and3"

  origin {
    domain_name = aws_lb.main.dns_name
    origin_id   = "alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    domain_name = aws_s3_bucket.static.bucket_regional_domain_name
    origin_id   = "s3"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.s3.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "alb"

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
      headers = ["*"]
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true
  }

  cache_behavior {
    path_pattern     = "/static/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = false
    acm_certificate_arn            = var.certificate_arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.cloudfront_logs.bucket_regional_domain_name
    prefix          = "cloudfront-logs"
  }

  tags = {
    Name = "resilience-cloudfront"
  }
}

resource "aws_cloudfront_origin_access_identity" "s3" {
  comment = "OAI for Resilience Weather S3"
}

resource "aws_s3_bucket" "cloudfront_logs" {
  bucket = "resilience-weather-cloudfront-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "resilience-cloudfront-logs"
  }
}

resource "aws_s3_bucket_versioning" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ──────────────────────────────────────
# CLOUDWATCH LOGGING
# ──────────────────────────────────────

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/resilience-weather"
  retention_in_days = 30

  tags = {
    Name = "resilience-ecs-logs"
  }
}

# ──────────────────────────────────────
# SECRETS MANAGER
# ──────────────────────────────────────

resource "aws_secretsmanager_secret" "session_secret" {
  name                    = "resilience/session-secret"
  recovery_window_in_days = 7

  tags = {
    Name = "resilience-session-secret"
  }
}

resource "aws_secretsmanager_secret_version" "session_secret" {
  secret_id = aws_secretsmanager_secret.session_secret.id
  secret_string = jsonencode({
    SESSION_SECRET = random_password.session_secret.result
  })
}

resource "random_password" "session_secret" {
  length  = 64
  special = true
}

resource "aws_secretsmanager_secret" "db_connection" {
  name                    = "resilience/database-url"
  recovery_window_in_days = 7

  tags = {
    Name = "resilience-db-connection"
  }
}

resource "aws_secretsmanager_secret_version" "db_connection" {
  secret_id = aws_secretsmanager_secret.db_connection.id
  secret_string = jsonencode({
    DATABASE_URL = "postgresql://${aws_db_instance.postgres.username}:${random_password.db_password.result}@${aws_db_instance.postgres.endpoint}:5432/${aws_db_instance.postgres.db_name}"
  })
}

# ──────────────────────────────────────
# IAM ROLES & POLICIES
# ──────────────────────────────────────

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "resilience-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "resilience-ecs-task-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_role_policy" {
  name = "resilience-ecs-task-execution-policy"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.session_secret.arn,
          aws_secretsmanager_secret.db_connection.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = [
          aws_kms_key.s3.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task_role" {
  name = "resilience-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "resilience-ecs-task-role"
  }
}

resource "aws_iam_role_policy" "ecs_task_role_policy" {
  name = "resilience-ecs-task-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.static.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.ecs.arn}:*"
      }
    ]
  })
}

# ──────────────────────────────────────
# CLOUDTRAIL (FEDERAL AUDIT COMPLIANCE)
# ──────────────────────────────────────

resource "aws_cloudtrail" "resilience" {
  name                          = "resilience-weather-audit-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  depends_on                    = [aws_s3_bucket_policy.cloudtrail]

  tags = {
    Name = "resilience-cloudtrail"
  }
}

resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket = "resilience-weather-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "resilience-cloudtrail-logs"
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}
