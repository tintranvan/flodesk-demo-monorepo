#!/bin/bash

set -e

SERVICE=${1:-api-svc-a}
ENVIRONMENT=${2:-dev}
AWS_PROFILE=${3:-esoftvn-researching}

echo " CI/CD Pipeline: $SERVICE  $ENVIRONMENT"
export AWS_PROFILE=$AWS_PROFILE

# Check service exists
if [ ! -d "cmd/$SERVICE" ]; then
    echo " Service cmd/$SERVICE not found"
    exit 1
fi

# 1. Build service in service directory
echo " 1/5 Building service..."
cd cmd/$SERVICE
mkdir -p .build
GOOS=linux GOARCH=arm64 go build -o .build/bootstrap main.go
cd .build && zip $SERVICE.zip bootstrap && cd ..
echo " Built .build/$SERVICE.zip ($(ls -lh .build/$SERVICE.zip | awk '{print $5}'))"

# 2. Generate Terraform from service.yaml in service directory
echo " 2/5 Generating Terraform from service.yaml..."
if [ ! -d "../../../flodesk-infra" ]; then
    cd ../../.. && git clone https://github.com/tintranvan/flodesk-demo-infra.git flodesk-infra && cd flodesk-monorepo/cmd/$SERVICE
fi

cd ../../../flodesk-infra
python3 scripts/generate-service-infra.py ../flodesk-monorepo/cmd/$SERVICE $ENVIRONMENT
echo " Terraform generated in cmd/$SERVICE/.terraform/"

# 3. Deploy infrastructure from service directory
echo " 3/5 Deploying infrastructure..."
cd ../flodesk-monorepo/cmd/$SERVICE/.terraform

# Copy zip file to terraform directory
cp ../.build/$SERVICE.zip ./

# Deploy
terraform init
terraform plan -out=tfplan
terraform apply -auto-approve tfplan
echo " Infrastructure deployed"

# 4. Lambda deployed via Terraform
echo " 4/5 Lambda deployed via Terraform"

# 5. Cleanup and get outputs
echo " 5/5 Cleanup and outputs..."
LAMBDA_ARN=$(terraform output -raw lambda_arn 2>/dev/null || echo "Check AWS Console")
API_URL="https://raznxe6xd7.execute-api.us-east-1.amazonaws.com/latest"

# Deploy API Gateway stage latest
echo " Deploying API Gateway stage 'latest'..."
aws apigateway create-deployment --rest-api-id raznxe6xd7 --stage-name latest --region us-east-1 --profile $AWS_PROFILE >/dev/null 2>&1 || echo "Stage deployment may already exist"

# Health check and rollback
echo " Health check..."
CURRENT_VERSION=$(aws lambda get-alias --function-name dev-$SERVICE --name latest --region us-east-1 --profile $AWS_PROFILE --query 'FunctionVersion' --output text)
sleep 5  # Wait for deployment to stabilize

# Test health endpoint
HEALTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" $API_URL/api-svc-a/health || echo "000")

if [ "$HEALTH_RESPONSE" != "200" ]; then
    echo " Health check failed (HTTP $HEALTH_RESPONSE)"
    
    # Get previous version
    PREVIOUS_VERSION=$(aws lambda list-versions-by-function --function-name dev-$SERVICE --region us-east-1 --profile $AWS_PROFILE --query 'Versions[?Version!=`$LATEST`]|[-2].Version' --output text)
    
    if [ "$PREVIOUS_VERSION" != "None" ] && [ "$PREVIOUS_VERSION" != "" ]; then
        echo " Rolling back to version $PREVIOUS_VERSION..."
        aws lambda update-alias --function-name dev-$SERVICE --name latest --function-version $PREVIOUS_VERSION --region us-east-1 --profile $AWS_PROFILE >/dev/null
        aws apigateway create-deployment --rest-api-id raznxe6xd7 --stage-name latest --region us-east-1 --profile $AWS_PROFILE >/dev/null
        echo " Rollback completed"
    else
        echo " No previous version available for rollback"
    fi
    exit 1
else
    echo " Health check passed (HTTP $HEALTH_RESPONSE)"
fi

# Cleanup build artifacts but keep terraform state
cd ..
rm -rf .build/ *.zip bootstrap 2>/dev/null || true

echo ""
echo " CI/CD Pipeline Completed!"
echo " Summary:"
echo "   Service built and packaged"
echo "   Terraform generated from service.yaml"
echo "   Infrastructure deployed"
echo "   Lambda function deployed"
echo "   Cleanup completed"
echo " Lambda ARN: $LAMBDA_ARN"
echo " API Gateway: $API_URL"
