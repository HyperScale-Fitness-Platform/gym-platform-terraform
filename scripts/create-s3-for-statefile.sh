#!/usr/bin/env bash
set -e

AWS_REGION="us-east-1"
BUCKET_NAME="gym-platform-tfstate-bucket"
LOCK_TABLE="gym-platform-tfstate-locks"

# 1. Create S3 Bucket only if it doesn't exist
if aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" 2>/dev/null; then
  echo "✓ S3 Bucket '$BUCKET_NAME' already exists."
else
  echo "Creating S3 Bucket '$BUCKET_NAME'..."
  aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$AWS_REGION"

  echo "Enabling Versioning..."
  aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled

  echo "Enabling Server-Side Encryption..."
  aws s3api put-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
  
  echo "✓ S3 Bucket created and configured."
fi

# 2. Create DynamoDB Table only if it doesn't exist
if aws dynamodb describe-table --table-name "$LOCK_TABLE" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "✓ DynamoDB Table '$LOCK_TABLE' already exists."
else
  echo "Creating DynamoDB Table '$LOCK_TABLE'..."
  aws dynamodb create-table \
    --table-name "$LOCK_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$AWS_REGION"
  
  echo "✓ DynamoDB Table created."
fi

echo "✓ S3 Bucket and DynamoDB Lock Table ready."