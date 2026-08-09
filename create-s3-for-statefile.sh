# Set your variables
AWS_REGION="us-east-1"
BUCKET_NAME="gym-platform-tfstate-bucket"  # Change this to your unique bucket name
LOCK_TABLE="gym-platform-tfstate-locks"

# 1. Create the S3 Bucket
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$AWS_REGION"

# 2. Enable Bucket Versioning (Protects against state corruption)
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

# 3. Enable Server-Side Encryption (AES256)
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'

# 4. Create DynamoDB Table for State Locking
aws dynamodb create-table \
  --table-name "$LOCK_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$AWS_REGION"

echo "✓ S3 Bucket and DynamoDB Lock Table created successfully."