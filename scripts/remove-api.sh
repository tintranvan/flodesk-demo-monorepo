#!/bin/bash

if [ $# -ne 2 ]; then
    echo "Usage: $0 <service-name> <environment>"
    echo "Example: $0 api-svc-a dev"
    exit 1
fi

SERVICE_NAME=$1
ENVIRONMENT=$2

echo "⚠️  WARNING: This will destroy $ENVIRONMENT-$SERVICE_NAME and all its resources!"
echo "Resources to be destroyed:"
echo "  - Lambda Function"
echo "  - API Gateway Routes"
echo "  - EventBridge Bus & Rules"
echo "  - IAM Roles & Policies"
echo "  - Secrets Manager"

read -p "Are you sure? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

cd cmd/$SERVICE_NAME/.terraform

echo "🗑️  Destroying infrastructure..."
terraform destroy -auto-approve

echo "✅ $ENVIRONMENT-$SERVICE_NAME removed successfully"
