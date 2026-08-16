#!/usr/bin/env bash
set -e

AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
BUCKET_NAME="gym-platform-tfstate-${AWS_ACCOUNT_ID}"
LOCK_TABLE="gym-platform-tfstate-locks"

# 1. Delete S3 Bucket and versioned objects
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "Deleting all object versions from '$BUCKET_NAME'..."
  aws s3 rm "s3://${BUCKET_NAME}" --recursive 2>/dev/null || true
  
  # Remove remaining version markers if versioning was enabled
  aws s3api delete-objects \
    --bucket "$BUCKET_NAME" \
    --delete "$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json)" 2>/dev/null || true

  aws s3api delete-objects \
    --bucket "$BUCKET_NAME" \
    --delete "$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json)" 2>/dev/null || true

  echo "Deleting S3 Bucket '$BUCKET_NAME'..."
  aws s3api delete-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"
fi

# 2. Delete DynamoDB table
if aws dynamodb describe-table --table-name "$LOCK_TABLE" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "Deleting DynamoDB table '$LOCK_TABLE'..."
  aws dynamodb delete-table --table-name "$LOCK_TABLE" --region "$AWS_REGION"
fi

echo "✓ S3 and DynamoDB resources successfully destroyed."