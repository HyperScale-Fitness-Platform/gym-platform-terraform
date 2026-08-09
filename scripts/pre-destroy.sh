#!/usr/bin/env bash

set -e

REGION="us-east-1"
ECR_REPOS=("gym-api-gateway" "gym-auth-service")
BUCKET_NAME="gym-platform-tfstate-bucket"
LOCK_TABLE="gym-platform-tfstate-locks"

echo "🚀 Starting Pre-Destroy Cleanup Script..."

# ------------------------------------------------------------------
# 1. Purge ECR Images
# ------------------------------------------------------------------
echo "📦 Step 1: Cleaning up ECR Repositories..."
for repo in "${ECR_REPOS[@]}"; do
  echo "  -> Checking repository: $repo"
  
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

# ------------------------------------------------------------------
# 2. Empty & Delete S3 Backend Bucket
# ------------------------------------------------------------------
echo "🪣 Step 2: Cleaning up S3 Remote State Bucket..."
if aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "  -> Purging all object versions and markers from $BUCKET_NAME..."
  
  # S3 buckets with versioning enabled require deleting all versions and delete-markers
  aws s3api delete-objects \
    --bucket "$BUCKET_NAME" \
    --delete "$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --region "$REGION" --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json)" >/dev/null 2>&1 || true

  aws s3api delete-objects \
    --bucket "$BUCKET_NAME" \
    --delete "$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --region "$REGION" --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json)" >/dev/null 2>&1 || true

  # Fallback force remove for any unversioned leftovers
  aws s3 rm "s3://$BUCKET_NAME" --recursive --region "$REGION" >/dev/null 2>&1 || true

  echo "  -> Deleting bucket $BUCKET_NAME..."
  aws s3api delete-bucket --bucket "$BUCKET_NAME" --region "$REGION"
  echo "  ✓ S3 bucket $BUCKET_NAME deleted."
else
  echo "  ✓ S3 bucket $BUCKET_NAME not found, skipping."
fi

# ------------------------------------------------------------------
# 3. Delete DynamoDB Lock Table
# ------------------------------------------------------------------
echo "🔒 Step 3: Cleaning up DynamoDB State Lock Table..."
if aws dynamodb describe-table --table-name "$LOCK_TABLE" --region "$REGION" >/dev/null 2>&1; then
  echo "  -> Deleting table $LOCK_TABLE..."
  aws dynamodb delete-table --table-name "$LOCK_TABLE" --region "$REGION" >/dev/null
  echo "  ✓ DynamoDB table $LOCK_TABLE deletion initiated."
else
  echo "  ✓ DynamoDB table $LOCK_TABLE not found, skipping."
fi

echo "✅ Pre-destroy cleanup completed successfully!"