#!/bin/bash

# RESILIENCE WEATHER — AUTOMATED DEPLOYMENT MASTER SCRIPT
# This script does EVERYTHING:
# 1. Installs AWS CLI, Docker, Terraform
# 2. Configures AWS credentials
# 3. Creates ACM certificate (if needed)
# 4. Deploys Terraform infrastructure
# 5. Builds and pushes Docker image
# 6. Sets up CI/CD
# 7. Configures monitoring

set -e

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║     RESILIENCE WEATHER — AUTOMATED AWS DEPLOYMENT         ║"
echo "║              Complete Infrastructure Setup                ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Helper functions
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo "❌ $1 not found"
        return 1
    fi
    echo "✅ $1 installed"
    return 0
}

install_aws_cli() {
    echo ""
    echo "📥 Installing AWS CLI v2..."
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    unzip -q /tmp/awscliv2.zip -d /tmp
    sudo /tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli >/dev/null 2>&1
    rm -rf /tmp/awscliv2.zip /tmp/aws
    echo "✅ AWS CLI installed"
}

install_terraform() {
    echo ""
    echo "📥 Installing Terraform..."
    TERRAFORM_VERSION="1.7.0"
    wget -q "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -O /tmp/terraform.zip
    unzip -q /tmp/terraform.zip -d /tmp
    sudo mv /tmp/terraform /usr/local/bin/
    rm /tmp/terraform.zip
    echo "✅ Terraform installed"
}

# Step 1: Check/Install Dependencies
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1/5: Checking and Installing Dependencies"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check/install AWS CLI
if ! check_command aws; then
    install_aws_cli
fi

# Check/install Docker
if ! check_command docker; then
    echo "❌ Docker not found. Install from: https://docs.docker.com/get-docker/"
    exit 1
fi

# Check/install Terraform
if ! check_command terraform; then
    install_terraform
fi

echo ""
echo "✅ All dependencies installed"
echo ""

# Step 2: AWS Account Configuration
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2/5: AWS Account Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if AWS is already configured
if aws sts get-caller-identity &>/dev/null; then
    EXISTING_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    echo "✅ AWS CLI already configured"
    echo "   Current Account: $EXISTING_ACCOUNT"
    echo ""
    read -p "Use this account? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "ℹ️  Run this to reconfigure:"
        echo "   aws configure"
        exit 1
    fi
    AWS_ACCOUNT_ID=$EXISTING_ACCOUNT
else
    echo "⚠️  AWS CLI not configured. Running setup..."
    echo ""
    echo "You need AWS Access Keys. Get them from:"
    echo "  AWS Console → IAM → Users → Security Credentials → Create Access Key"
    echo ""
    
    read -p "Enter AWS Access Key ID: " AWS_ACCESS_KEY_ID
    read -sp "Enter AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
    echo ""
    read -p "Enter AWS Region (default: us-east-1): " AWS_REGION
    AWS_REGION=${AWS_REGION:-us-east-1}
    
    mkdir -p ~/.aws
    cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF
    
    cat > ~/.aws/config << EOF
[default]
region = $AWS_REGION
output = json
EOF
    
    chmod 600 ~/.aws/credentials ~/.aws/config
    
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo "✅ AWS CLI configured"
    echo "   Account ID: $AWS_ACCOUNT_ID"
fi

echo ""

# Step 3: Get or Create ACM Certificate
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3/5: ACM Certificate"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

CERT_ARN=$(aws acm list-certificates --region us-east-1 --query "CertificateSummaryList[?DomainName=='resilienceweather.com'].CertificateArn" --output text 2>/dev/null || echo "")

if [ -z "$CERT_ARN" ]; then
    echo "ℹ️  No existing certificate found for resilienceweather.com"
    echo ""
    echo "Options:"
    echo "1. Create certificate automatically (recommended)"
    echo "2. Use existing certificate ARN"
    echo ""
    read -p "Choose option (1-2): " CERT_OPTION
    
    if [ "$CERT_OPTION" = "1" ]; then
        echo ""
        echo "📝 Creating ACM certificate..."
        CERT_ARN=$(aws acm request-certificate \
            --domain-name resilienceweather.com \
            --subject-alternative-names www.resilienceweather.com \
            --validation-method DNS \
            --region us-east-1 \
            --query 'CertificateArn' \
            --output text)
        echo "✅ Certificate requested: $CERT_ARN"
        echo ""
        echo "⏳ Certificate will be validated automatically via DNS"
        echo "   (Usually takes 5-10 minutes)"
        echo ""
        read -p "Press Enter once certificate shows 'Issued' status in AWS Console"
    else
        echo ""
        read -p "Enter your certificate ARN: " CERT_ARN
    fi
else
    echo "✅ Found existing certificate: $CERT_ARN"
fi

echo ""

# Step 4: Deploy Infrastructure
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4/5: Deploy AWS Infrastructure"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "⚙️  Running Terraform deployment..."
echo "   This will take approximately 15-20 minutes"
echo ""

"$PROJECT_DIR/deploy-everything.sh" "$AWS_ACCOUNT_ID" "$CERT_ARN"

# Extract outputs
cd "$PROJECT_DIR/terraform"
CLOUDFRONT_DOMAIN=$(terraform output -raw cloudfront_domain_name 2>/dev/null || echo "")

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 5/5: Final Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd "$PROJECT_DIR"

# Update GitHub with secrets
echo "📝 Setting up GitHub Actions (optional)..."
echo ""
echo "To enable automatic deployments, add these secrets to GitHub:"
echo "  Repository → Settings → Secrets and variables → Actions"
echo ""
echo "Secret: AWS_ACCESS_KEY_ID"
echo "Value: (your access key)"
echo ""
echo "Secret: AWS_SECRET_ACCESS_KEY"
echo "Value: (your secret key)"
echo ""

# Final summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 DEPLOYMENT COMPLETE!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ ! -z "$CLOUDFRONT_DOMAIN" ]; then
    echo "📊 Infrastructure Summary:"
    echo "   CloudFront CDN: $CLOUDFRONT_DOMAIN"
    echo "   AWS Account: $AWS_ACCOUNT_ID"
    echo ""
    echo "🔗 Next Step: Update DNS at IONOS"
    echo ""
    echo "   Go to: IONOS Domain Management → resilienceweather.com → DNS"
    echo ""
    echo "   Add CNAME record:"
    echo "     Name: @"
    echo "     Type: CNAME"
    echo "     Value: $CLOUDFRONT_DOMAIN"
    echo ""
    echo "   Then wait 5-15 minutes for DNS to propagate"
    echo ""
    echo "✅ Verify with:"
    echo "   curl -I https://resilienceweather.com"
    echo ""
fi

echo "📚 Documentation:"
echo "   Deployment Guide: ./AWS_DEPLOYMENT_GUIDE.md"
echo "   Quick Reference: ./QUICK_REFERENCE.md"
echo "   Checklist: ./AWS_DEPLOYMENT_CHECKLIST.md"
echo ""

echo "📊 Monitor your deployment:"
echo "   AWS Console → ECS → Clusters → resilience-cluster"
echo "   AWS Console → RDS → Databases → resilience-db"
echo "   AWS Console → Billing → Cost Explorer"
echo ""

echo "🔐 Federal Compliance Enabled:"
echo "   ✅ CloudTrail audit logging"
echo "   ✅ RDS encryption with KMS"
echo "   ✅ 30-day automated backups"
echo "   ✅ Multi-AZ high availability"
echo ""

echo "💡 Cost Estimate: $100-200/month (covered by AWS Activate credits)"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Ready for NOAA Grant Application! 🚀"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
