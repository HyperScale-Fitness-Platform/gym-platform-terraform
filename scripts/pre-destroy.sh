#!/usr/bin/env bash

set -e

REGION="us-east-1"
ECR_REPOS=("gym-api-gateway" "gym-auth-service")

echo "🚀 Starting Pre-Destroy Cleanup Script..."

# ------------------------------------------------------------------
# Purge ECR Images
# ------------------------------------------------------------------
echo "📦 Step 1: Cleaning up ECR Repositories..."
for repo in "${ECR_REPOS[@]}"; do
  echo "  -> Checking repository: $repo"
  
  # Verify repo exists before listing images
  if aws ecr describe-repositories --region "$REGION" --repository-names "$repo" >/dev/null 2>&1; then
    IMAGES=$(aws ecr list-images --region "$REGION" --repository-name "$repo" --query 'imageIds[*]' --output json 2>/dev/null || echo "[]")
    
    if [ "$IMAGES" != "[]" ] && [ -n "$IMAGES" ]; then
      echo "     Purging images from $repo..."
      aws ecr batch-delete-image --region "$REGION" --repository-name "$repo" --image-ids "$IMAGES" >/dev/null
      echo "     ✓ Images deleted from $repo."
    else
      echo "     ✓ $repo is already empty."
    fi
  else
    echo "     ✓ Repository $repo not found in AWS, skipping."
  fi
done
EOF