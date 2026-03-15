#!/bin/bash

# AWS CLI Credentials Setup Helper
# This script securely configures AWS CLI with your credentials

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 AWS CLI Credentials Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⚠️  You need AWS credentials from your account:"
echo "   AWS Console → IAM → Users → Security Credentials → Create Access Key"
echo ""
echo "Get your credentials from:"
echo "   https://console.aws.amazon.com/iam/home?#/users/"
echo ""
echo "Then enter them below (passwords will NOT be displayed):"
echo ""

# Get credentials
read -p "Enter AWS Access Key ID: " AWS_ACCESS_KEY_ID
read -sp "Enter AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
echo ""
read -p "Enter AWS Region (default: us-east-1): " AWS_REGION
AWS_REGION=${AWS_REGION:-us-east-1}

echo ""
echo "Configuring AWS CLI..."

# Create credentials file
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

chmod 600 ~/.aws/credentials
chmod 600 ~/.aws/config

echo "✅ Credentials configured!"
echo ""
echo "Verifying..."

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)

if [ $? -eq 0 ]; then
    echo "✅ AWS CLI authenticated successfully!"
    echo "   Account ID: $ACCOUNT_ID"
    echo ""
    echo "Now you're ready to deploy:"
    echo "   ./deploy-everything.sh $ACCOUNT_ID <CERTIFICATE_ARN>"
else
    echo "❌ Authentication failed. Check your credentials and try again."
    exit 1
fi
