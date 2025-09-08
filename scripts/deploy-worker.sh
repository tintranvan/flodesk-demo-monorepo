#!/bin/bash

set -e

SERVICE=$1
ENVIRONMENT=$2
AWS_PROFILE=${3:-esoftvn-researching}

if [ -z "$SERVICE" ] || [ -z "$ENVIRONMENT" ]; then
    echo "Usage: ./deploy-worker.sh <service> <environment> [aws-profile]"
    echo "Example: ./deploy-worker.sh worker-c dev"
    exit 1
fi

export AWS_PROFILE=$AWS_PROFILE

echo " CI/CD Pipeline: $SERVICE  $ENVIRONMENT"

# 1. Build Docker image
echo " 1/5 Building Docker image..."
cd cmd/$SERVICE

# Generate image tag with timestamp
IMAGE_TAG="v$(date +%Y%m%d_%H%M%S)_$(git rev-parse --short HEAD 2>/dev/null || echo 'local')"
REPO_NAME="$SERVICE-$ENVIRONMENT"
ECR_URI="647272350116.dkr.ecr.us-east-1.amazonaws.com/$REPO_NAME"

# Build and tag image using shared Dockerfile.worker
docker build --platform linux/arm64 \
  -f ../Dockerfile.worker \
  --build-arg SERVICE_NAME=$SERVICE \
  --build-arg TARGETARCH=arm64 \
  -t $SERVICE:$IMAGE_TAG ../
docker tag $SERVICE:$IMAGE_TAG $ECR_URI:$IMAGE_TAG
docker tag $SERVICE:$IMAGE_TAG $ECR_URI:latest

echo " Built Docker image with tag: $IMAGE_TAG"

# 2. Push to ECR
echo " 2/5 Pushing to ECR..."

# Login to ECR
aws ecr get-login-password --region us-east-1 --profile $AWS_PROFILE | docker login --username AWS --password-stdin 647272350116.dkr.ecr.us-east-1.amazonaws.com

# Create repository if not exists (will be managed by Terraform after first deploy)
aws ecr describe-repositories --repository-names $REPO_NAME --region us-east-1 --profile $AWS_PROFILE >/dev/null 2>&1 || \
aws ecr create-repository --repository-name $REPO_NAME --region us-east-1 --profile $AWS_PROFILE

# Push image
docker push $ECR_URI:$IMAGE_TAG
docker push $ECR_URI:latest

echo " Pushed to ECR with tags: $IMAGE_TAG, latest"

# 3. Generate Terraform
echo " 3/5 Generating Terraform from service.yaml..."
cd ../..
python3 ../flodesk-infra/scripts/generate-worker-infra.py ./cmd/$SERVICE $ENVIRONMENT
echo " Terraform generated in cmd/$SERVICE/.terraform/"

# 4. Deploy infrastructure
echo " 4/5 Deploying infrastructure..."
cd cmd/$SERVICE/.terraform

# Replace image tag in terraform with actual tag
sed -i.bak "s|:v\$(date.*)|:$IMAGE_TAG|g" main.tf

# Initialize Terraform
terraform init

# Plan and apply
terraform plan -out=tfplan
terraform apply tfplan

echo " Infrastructure deployed"

# 5. Deploy with ECS rolling update
echo " 5/5 Deploying with ECS rolling update..."
SERVICE_NAME="$ENVIRONMENT-$SERVICE"
CLUSTER_NAME=$(terraform output -raw cluster_name)

# Get current task definition for rollback
echo " Saving current state for rollback..."
PREVIOUS_TASK_DEF=$(aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME \
    --region us-east-1 \
    --profile $AWS_PROFILE \
    --query 'services[0].taskDefinition' \
    --output text 2>/dev/null || echo "")

echo "  Previous task definition: $PREVIOUS_TASK_DEF"

# ECS will handle the rolling update automatically based on deployment_configuration
# minimum_healthy_percent=0 allows stopping all old tasks
# maximum_percent=100 ensures no extra tasks beyond desired count
echo " Starting ECS rolling deployment..."
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --force-new-deployment \
    --region us-east-1 \
    --profile $AWS_PROFILE >/dev/null

echo " ECS deployment initiated"

# Health check with rollback capability
echo " Health check with rollback capability..."

for i in {1..30}; do  # 5 minutes max (30 * 10s)
    echo "  Health check attempt $i/30..."
    sleep 10
    
    SERVICE_STATUS=$(aws ecs describe-services \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --region us-east-1 \
        --profile $AWS_PROFILE \
        --query 'services[0].runningCount' \
        --output text)
    
    DESIRED_COUNT=$(aws ecs describe-services \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --region us-east-1 \
        --profile $AWS_PROFILE \
        --query 'services[0].desiredCount' \
        --output text)

    if [ "$SERVICE_STATUS" -ge "$DESIRED_COUNT" ]; then
        # Check deployment status
        DEPLOYMENT_STATUS=$(aws ecs describe-services \
            --cluster $CLUSTER_NAME \
            --services $SERVICE_NAME \
            --region us-east-1 \
            --profile $AWS_PROFILE \
            --query 'services[0].deployments[?status==`PRIMARY`].rolloutState' \
            --output text)
        
        if [ "$DEPLOYMENT_STATUS" = "COMPLETED" ]; then
            echo " Health check passed ($SERVICE_STATUS/$DESIRED_COUNT tasks running)"
            echo " Deployment completed successfully"
            break
        else
            echo "  Deployment status: $DEPLOYMENT_STATUS ($SERVICE_STATUS/$DESIRED_COUNT tasks)"
        fi
    else
        echo "  Status: $SERVICE_STATUS/$DESIRED_COUNT tasks running..."
    fi
    
    # If this is the last attempt, prepare for rollback
    if [ $i -eq 30 ]; then
        echo " Health check failed after 30 attempts"
        
        if [ ! -z "$PREVIOUS_TASK_DEF" ] && [ "$PREVIOUS_TASK_DEF" != "None" ]; then
            echo " Rolling back to previous task definition..."
            
            aws ecs update-service \
                --cluster $CLUSTER_NAME \
                --service $SERVICE_NAME \
                --task-definition $PREVIOUS_TASK_DEF \
                --region us-east-1 \
                --profile $AWS_PROFILE >/dev/null
                
            echo " Rollback initiated to $PREVIOUS_TASK_DEF"
        fi
        
        exit 1
    fi
done

# Cleanup
cd ../../..
rm -rf cmd/$SERVICE/.terraform/tfplan

echo ""
echo " CI/CD Pipeline Completed!"
echo " Summary:"
echo "   Docker image built and pushed"
echo "   Terraform generated from service.yaml"
echo "   Infrastructure deployed"
echo "   ECS service updated"
echo "   Health check passed"
echo " Service: $SERVICE_NAME"
echo " Queue: $(terraform output -raw queue_url)"
