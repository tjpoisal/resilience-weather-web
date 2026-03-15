#!/bin/bash

# Resilience Weather — Automated Docker Build & ECR Push
# Usage: ./deploy.sh [ECR_REPO_URL] [AWS_REGION]

set -e

ECR_REPO=${1:-"YOUR_ECR_REPO_URL"}
AWS_REGION=${2:-"us-east-1"}
IMAGE_NAME="resilience-weather"
IMAGE_TAG="latest"

if [ "$ECR_REPO" == "YOUR_ECR_REPO_URL" ]; then
    echo "❌ Usage: ./deploy.sh <ECR_REPO_URL> [AWS_REGION]"
    echo ""
    echo "Get ECR_REPO_URL from Terraform output or:"
    echo "  aws ecr describe-repositories --region $AWS_REGION | jq '.repositories[0].repositoryUri'"
    exit 1
fi

echo "🚀 Resilience Weather — Docker Build & ECR Deploy"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ECR Repository: $ECR_REPO"
echo "Region: $AWS_REGION"
echo ""

# Step 1: Authenticate with ECR
echo "📍 Step 1/4: Authenticating with ECR..."
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin $ECR_REPO
echo "✅ ECR authentication successful"
echo ""

# Step 2: Build Docker image
echo "📍 Step 2/4: Building Docker image..."
docker build \
    --tag $IMAGE_NAME:$IMAGE_TAG \
    --tag $IMAGE_NAME:$(date +%Y%m%d-%H%M%S) \
    --label "built-at=$(date -Iseconds)" \
    --label "git-commit=$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')" \
    .

if [ $? -ne 0 ]; then
    echo "❌ Docker build failed"
    exit 1
fi
echo "✅ Docker image built"
echo ""

# Step 3: Tag for ECR
echo "📍 Step 3/4: Tagging image for ECR..."
docker tag $IMAGE_NAME:$IMAGE_TAG $ECR_REPO:$IMAGE_TAG
docker tag $IMAGE_NAME:$IMAGE_TAG $ECR_REPO:$(date +%Y%m%d-%H%M%S)
echo "✅ Image tagged"
echo ""

# Step 4: Push to ECR
echo "📍 Step 4/4: Pushing to ECR..."
docker push $ECR_REPO:$IMAGE_TAG
PUSH_RESULT=$?

if [ $PUSH_RESULT -eq 0 ]; then
    echo "✅ Push successful"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🎉 Deployment complete!"
    echo ""
    echo "Next steps:"
    echo "1. ECS will auto-pull the new image (check task status)"
    echo "2. Verify deployment:"
    echo "   curl -I https://resilienceweather.com"
    echo ""
    echo "Monitor logs:"
    echo "   aws logs tail /ecs/resilience-weather --follow --region $AWS_REGION"
    echo ""
    echo "View metrics:"
    echo "   https://console.aws.amazon.com/ecs/home?region=$AWS_REGION#/clusters/resilience-cluster/services/resilience-service"
else
    echo "❌ Push failed"
    exit 1
fi
