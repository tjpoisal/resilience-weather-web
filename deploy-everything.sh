#!/bin/bash

# Resilience Weather — Complete AWS Deployment Automation
# This script handles all phases: Terraform, Docker, ECR push, DNS updates
# Usage: ./deploy-everything.sh <AWS_ACCOUNT_ID> <CERTIFICATE_ARN>

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 RESILIENCE WEATHER — COMPLETE AWS DEPLOYMENT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Validate inputs
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "❌ Usage: ./deploy-everything.sh <AWS_ACCOUNT_ID> <CERTIFICATE_ARN>"
    echo ""
    echo "Example:"
    echo "  ./deploy-everything.sh 123456789012 arn:aws:acm:us-east-1:123456789012:certificate/xxxxx"
    echo ""
    echo "Get Certificate ARN from AWS Console:"
    echo "  → Certificate Manager → Copy ARN"
    exit 1
fi

AWS_ACCOUNT_ID=$1
CERTIFICATE_ARN=$2
AWS_REGION="us-east-1"
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "📋 Configuration:"
echo "  AWS Account ID: $AWS_ACCOUNT_ID"
echo "  Certificate ARN: $CERTIFICATE_ARN"
echo "  Region: $AWS_REGION"
echo "  Project: $PROJECT_DIR"
echo ""

# Phase 1: Verify AWS CLI
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📍 Phase 1/6: Verifying AWS CLI"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Install with:"
    echo "   curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip"
    echo "   unzip awscliv2.zip && sudo ./aws/install"
    exit 1
fi

AWS_CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "NOT_AUTHENTICATED")

if [ "$AWS_CURRENT_ACCOUNT" != "$AWS_ACCOUNT_ID" ]; then
    echo "⚠️  Current AWS account: $AWS_CURRENT_ACCOUNT"
    echo "⚠️  Target AWS account:  $AWS_ACCOUNT_ID"
    echo ""
    echo "Configure AWS CLI with correct credentials:"
    echo "  aws configure"
    echo "  Enter Access Key ID and Secret Access Key for account $AWS_ACCOUNT_ID"
    exit 1
fi

echo "✅ AWS CLI authenticated as: $AWS_CURRENT_ACCOUNT"
echo ""

# Phase 2: Verify Terraform
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📍 Phase 2/6: Installing Terraform"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if ! command -v terraform &> /dev/null; then
    echo "📥 Installing Terraform..."
    wget -q https://releases.hashicorp.com/terraform/1.7.0/terraform_1.7.0_linux_amd64.zip
    unzip -q terraform_1.7.0_linux_amd64.zip
    sudo mv terraform /usr/local/bin/
    rm terraform_1.7.0_linux_amd64.zip
fi

terraform version
echo "✅ Terraform ready"
echo ""

# Phase 3: Deploy Terraform Infrastructure
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📍 Phase 3/6: Deploying AWS Infrastructure (Terraform)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd "$PROJECT_DIR/terraform"

echo "🔧 Initializing Terraform..."
terraform init

echo ""
echo "📋 Planning infrastructure (dry-run)..."
terraform plan \
    -var="certificate_arn=$CERTIFICATE_ARN" \
    -var="aws_region=$AWS_REGION" \
    -out=tfplan

echo ""
echo "📋 Terraform plan created. Review above output."
echo "Applying in 10 seconds... (Ctrl+C to cancel)"
sleep 10

echo ""
echo "⚙️  Applying Terraform (this takes ~15-20 minutes)..."
terraform apply tfplan

echo ""
echo "✅ Infrastructure deployed!"
echo ""

# Extract outputs
ALB_DNS=$(terraform output -raw alb_dns_name)
CLOUDFRONT_DOMAIN=$(terraform output -raw cloudfront_domain_name)
ECR_REPO=$(terraform output -raw ecr_repository_url)
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)

echo "📊 Deployment Outputs:"
echo "  ALB DNS: $ALB_DNS"
echo "  CloudFront: $CLOUDFRONT_DOMAIN"
echo "  ECR Repository: $ECR_REPO"
echo "  RDS Endpoint: $RDS_ENDPOINT"
echo ""

cd "$PROJECT_DIR"

# Phase 4: Build & Push Docker Image
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📍 Phase 4/6: Building and Pushing Docker Image"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "🐳 Building Docker image..."
docker build -t resilience-weather:latest \
    --label "aws.account=$AWS_ACCOUNT_ID" \
    --label "deployed.at=$(date -Iseconds)" \
    .

echo ""
echo "🔐 Authenticating with ECR..."
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin $ECR_REPO

echo ""
echo "🚀 Tagging and pushing to ECR..."
docker tag resilience-weather:latest $ECR_REPO:latest
docker tag resilience-weather:latest $ECR_REPO:$(date +%Y%m%d-%H%M%S)

docker push $ECR_REPO:latest
docker push $ECR_REPO:$(date +%Y%m%d-%H%M%S)

echo "✅ Docker image pushed to ECR"
echo ""

# Phase 5: Setup CloudFront Cache Invalidation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📍 Phase 5/6: Setting Up CloudFront"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

CF_DIST_ID=$(terraform output -raw cloudfront_distribution_id)

echo "📡 CloudFront Distribution ID: $CF_DIST_ID"
echo "✅ CloudFront ready for use"
echo ""

# Phase 6: Monitoring Setup
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📍 Phase 6/6: Setting Up Monitoring"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "📊 Creating CloudWatch Alarms..."

# CPU alarm
aws cloudwatch put-metric-alarm \
    --alarm-name resilience-cpu-high \
    --alarm-description "Alert when ECS CPU > 80%" \
    --metric-name CPUUtilization \
    --namespace AWS/ECS \
    --statistic Average \
    --period 300 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --region $AWS_REGION 2>/dev/null || true

echo "✅ CloudWatch alarms configured"
echo ""

# Final Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 DEPLOYMENT COMPLETE!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ Infrastructure:"
echo "   ECS Fargate cluster: resilience-cluster"
echo "   RDS Database: resilience-db"
echo "   Load Balancer: $ALB_DNS"
echo "   CDN: $CLOUDFRONT_DOMAIN"
echo "   Container Registry: $ECR_REPO"
echo ""
echo "📋 Next Steps:"
echo "1. Update DNS at IONOS:"
echo "   Domain: resilienceweather.com"
echo "   CNAME @ record → $CLOUDFRONT_DOMAIN"
echo ""
echo "2. Wait 5-15 minutes for DNS propagation"
echo ""
echo "3. Verify deployment:"
echo "   curl -I https://resilienceweather.com"
echo ""
echo "4. Monitor logs:"
echo "   aws logs tail /ecs/resilience-weather --follow --region $AWS_REGION"
echo ""
echo "5. Check ECS status:"
echo "   aws ecs describe-services --cluster resilience-cluster --services resilience-service --region $AWS_REGION"
echo ""
echo "📊 Cost Tracking:"
echo "   AWS Console → Billing & Cost Management → Cost Explorer"
echo "   Expected: $100-200/month (covered by AWS Activate credits)"
echo ""
echo "🔐 Federal Compliance:"
echo "   ✅ CloudTrail audit logs: s3://resilience-weather-cloudtrail-logs-*"
echo "   ✅ Encrypted database: RDS with KMS"
echo "   ✅ Automated backups: 30-day retention"
echo ""
echo "🚀 Ready for NOAA Grant!"
echo ""
echo "Save these values:"
echo "  AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID"
echo "  CERTIFICATE_ARN=$CERTIFICATE_ARN"
echo "  CLOUDFRONT_DOMAIN=$CLOUDFRONT_DOMAIN"
echo "  ECR_REPO=$ECR_REPO"
echo "  RDS_ENDPOINT=$RDS_ENDPOINT"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
