#!/usr/bin/env bash
set -e

AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

# Dynamically retrieve the AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

BUCKET_NAME="gym-platform-tfstate-${AWS_ACCOUNT_ID}"
LOCK_TABLE="gym-platform-tfstate-locks"

echo "Using dynamic bucket name: ${BUCKET_NAME}"

# 1. Create S3 Bucket only if it doesn't exist
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "✓ S3 Bucket '$BUCKET_NAME' already exists and is owned by your account."
else
  echo "Creating S3 Bucket '$BUCKET_NAME'..."
  if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --region "$AWS_REGION"
  else
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --region "$AWS_REGION" \
      --create-bucket-configuration LocationConstraint="$AWS_REGION"
  fi

  echo "Enabling Versioning..."
  aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled

  echo "Enabling Server-Side Encryption..."
  aws s3api put-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'

  echo "Enabling Public Access Block..."
  aws s3api put-public-access-block \
    --bucket "$BUCKET_NAME" \
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
  
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