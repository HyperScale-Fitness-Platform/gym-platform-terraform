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
# 2. Clean Up AWS Load Balancers & Target Groups (Frees ENIs & IPs)
# ------------------------------------------------------------------
echo "🌐 Step 2: Cleaning up Application Load Balancers and Target Groups..."

# Find ALB ARNs created dynamically by Kubernetes Ingress / AWS LBC
ALB_ARNS=$(aws elbv2 describe-load-balancers --region "$REGION" \
  --query "LoadBalancers[?contains(LoadBalancerName, 'k8s-gymdev') || contains(LoadBalancerName, 'apigatew') || contains(LoadBalancerName, 'gym')].LoadBalancerArn" \
  --output text 2>/dev/null || true)

if [ -n "$ALB_ARNS" ]; then
  for alb_arn in $ALB_ARNS; do
    echo "  -> Deleting Load Balancer: $alb_arn"
    aws elbv2 delete-load-balancer --load-balancer-arn "$alb_arn" --region "$REGION"
  done
  echo "     Waiting 30 seconds for ALB ENIs to detach and release..."
  sleep 30
else
  echo "  ✓ No active ALB found."
fi

# Find and delete remaining Target Groups
TG_ARNS=$(aws elbv2 describe-target-groups --region "$REGION" \
  --query "TargetGroups[?contains(TargetGroupName, 'k8s-gymdev') || contains(TargetGroupName, 'api-gateway') || contains(TargetGroupName, 'gym')].TargetGroupArn" \
  --output text 2>/dev/null || true)

if [ -n "$TG_ARNS" ]; then
  for tg in $TG_ARNS; do
    echo "  -> Deleting Target Group: $tg"
    aws elbv2 delete-target-group --target-group-arn "$tg" --region "$REGION" 2>/dev/null || true
  done
  echo "     ✓ Target Groups deleted."
else
  echo "  ✓ No lingering Target Groups found."
fi

# ------------------------------------------------------------------
# 3. Dynamic VPC Discovery & Cleanup (ENIs & Security Groups)
# ------------------------------------------------------------------
echo "🧹 Step 3: Checking for lingering VPC resources..."

# Try to get VPC ID dynamically from terraform output or tag search
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || true)

if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "Warning:" ] || [[ "$VPC_ID" == *"No outputs"* ]]; then
  VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" \
    --filters "Name=tag:Name,Values=*gym-vpc*" \
    --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "None")
fi

if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ] && [ "$VPC_ID" != "null" ]; then
  echo "  -> Target VPC identified: $VPC_ID"

  # Display remaining ENIs before forced cleanup
  echo "  -> Remaining Network Interfaces in $VPC_ID:"
  aws ec2 describe-network-interfaces --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "NetworkInterfaces[*].[NetworkInterfaceId,Description,Status]" \
    --output table 2>/dev/null || true

  # Detach and delete any remaining Network Interfaces (ENIs)
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

  # Delete custom security groups created by EKS / AWS LBC
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
EOF

chmod +x pre-destroy-cleanup.sh