#!/usr/bin/env bash
set -e

REGION="us-east-1"
BUCKET_NAME="gym-platform-tfstate-bucket"
LOCK_TABLE="gym-platform-tfstate-locks"

echo "🪣 Deleting S3 Remote State Bucket & DynamoDB Lock Table..."

if aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$REGION" >/dev/null 2>&1; then
  aws s3api delete-objects \
    --bucket "$BUCKET_NAME" \
    --delete "$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --region "$REGION" --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json)" >/dev/null 2>&1 || true

  aws s3api delete-objects \
    --bucket "$BUCKET_NAME" \
    --delete "$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --region "$REGION" --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json)" >/dev/null 2>&1 || true

  aws s3 rm "s3://$BUCKET_NAME" --recursive --region "$REGION" >/dev/null 2>&1 || true
  aws s3api delete-bucket --bucket "$BUCKET_NAME" --region "$REGION"
  echo "✓ S3 bucket $BUCKET_NAME deleted."
fi

if aws dynamodb describe-table --table-name "$LOCK_TABLE" --region "$REGION" >/dev/null 2>&1; then
  aws dynamodb delete-table --table-name "$LOCK_TABLE" --region "$REGION" >/dev/null
  echo "✓ DynamoDB table $LOCK_TABLE deleted."
fi