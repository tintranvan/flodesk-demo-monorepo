#!/bin/bash

set -e

SERVICE=${1:-}
ENVIRONMENT=${2:-dev}
AWS_PROFILE=${3:-esoftvn-researching}

if [ -z "$SERVICE" ]; then
    echo "Usage: ./remove-service.sh <service-name> [environment] [aws-profile]"
    echo "Example: ./remove-service.sh api-svc-a dev esoftvn-researching"
    exit 1
fi

echo "🗑️  Removing service: $SERVICE from $ENVIRONMENT"
export AWS_PROFILE=$AWS_PROFILE

# Check if service exists
if [ ! -d "cmd/$SERVICE" ]; then
    echo "❌ Service cmd/$SERVICE not found"
    exit 1
fi

# Check if terraform directory exists
if [ ! -d "cmd/$SERVICE/.terraform" ]; then
    echo "❌ No terraform state found for $SERVICE"
    exit 1
fi

echo "⚠️  This will destroy all AWS resources for $SERVICE in $ENVIRONMENT"
read -p "Are you sure? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Cancelled"
    exit 1
fi

# Destroy infrastructure
echo "🗑️  1/2 Destroying infrastructure..."
cd cmd/$SERVICE/.terraform

terraform destroy -auto-approve
echo "✅ Infrastructure destroyed"

# Clean up terraform files
echo "🧹 2/2 Cleaning up..."
cd ..
rm -rf .terraform/ .build/ *.zip bootstrap 2>/dev/null || true

echo ""
echo "🎉 Service $SERVICE removed successfully!"
echo "📊 Summary:"
echo "  ✅ AWS resources destroyed"
echo "  ✅ Terraform state cleaned"
echo "  ✅ Build artifacts removed"
