cat << 'EOF' > pre-destroy-cleanup.sh
#!/usr/bin/env bash

set -e

REGION="us-east-1"
ECR_REPOS=("gym-api-gateway" "gym-auth-service")

echo "🚀 Starting Pre-Destroy Cleanup Script..."

# ------------------------------------------------------------------
# 1. Purge ECR Images
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

# ------------------------------------------------------------------
# 2. Dynamic VPC Discovery & Cleanup (ENIs & Security Groups)
# ------------------------------------------------------------------
echo "🧹 Step 2: Checking for lingering VPC resources..."

# Try to get VPC ID dynamically from terraform output or tag search
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || true)

if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "Warning:" ]; then
  VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" \
    --filters "Name=tag:Name,Values=*gym-vpc*" \
    --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "None")
fi

if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ] && [ "$VPC_ID" != "null" ]; then
  echo "  -> Target VPC identified: $VPC_ID"

  # Detach and delete Network Interfaces (ENIs) created by ALBs/EKS
  echo "  -> Clearing Network Interfaces (ENIs)..."
  ENIS=$(aws ec2 describe-network-interfaces --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "NetworkInterfaces[*].NetworkInterfaceId" --output text 2>/dev/null || true)

  if [ -n "$ENIS" ]; then
    for eni in $ENIS; do
      ATTACHMENT=$(aws ec2 describe-network-interfaces --region "$REGION" \
        --network-interface-ids "$eni" \
        --query "NetworkInterfaces[0].Attachment.AttachmentId" --output text 2>/dev/null || true)

      if [ "$ATTACHMENT" != "None" ] && [ -n "$ATTACHMENT" ]; then
        aws ec2 detach-network-interface --region "$REGION" --attachment-id "$ATTACHMENT" --force 2>/dev/null || true
        sleep 2
      fi

      aws ec2 delete-network-interface --region "$REGION" --network-interface-id "$eni" 2>/dev/null \
        && echo "     ✓ Deleted ENI: $eni" \
        || echo "     ⚠️ ENI $eni queued for deletion/release."
    done
  else
    echo "     ✓ No active ENIs found."
  fi

  # Delete custom security groups created by EKS/LBC
  echo "  -> Clearing non-default Security Groups..."
  SGS=$(aws ec2 describe-security-groups --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "SecurityGroups[?GroupName!='default'].GroupId" --output text 2>/dev/null || true)

  if [ -n "$SGS" ]; then
    for sg in $SGS; do
      aws ec2 delete-security-group --region "$REGION" --group-id "$sg" 2>/dev/null \
        && echo "     ✓ Deleted Security Group: $sg" \
        || echo "     ⚠️ Failed to delete Security Group: $sg (may have dependencies)"
    done
  else
    echo "     ✓ No custom Security Groups found."
  fi
else
  echo "  ✓ No target VPC found or already deleted."
fi

# ------------------------------------------------------------------
# 3. Execute Terraform Destroy
# ------------------------------------------------------------------
echo "🔥 Step 3: Running terraform destroy..."
terraform destroy
EOF

chmod +x pre-destroy-cleanup.sh