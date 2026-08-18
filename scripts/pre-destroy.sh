#!/usr/bin/env bash
set -e

REGION="us-east-1"
ECR_REPOS=("gym-api-gateway" "gym-auth-service")

echo "🚀 Starting Pre-Destroy Cleanup Script..."

# 1. Purge ECR Images
echo "📦 Step 1: Cleaning up ECR Repositories..."
for repo in "${ECR_REPOS[@]}"; do
  if aws ecr describe-repositories --region "$REGION" --repository-names "$repo" >/dev/null 2>&1; then
    IMAGES=$(aws ecr list-images --region "$REGION" --repository-name "$repo" --query 'imageIds[*]' --output json 2>/dev/null || echo "[]")
    if [ "$IMAGES" != "[]" ] && [ -n "$IMAGES" ]; then
      aws ecr batch-delete-image --region "$REGION" --repository-name "$repo" --image-ids "$IMAGES" >/dev/null
      echo "     ✓ Images deleted from $repo."
    fi
  fi
done

# 2. Delete ALBs and wait for ENI release
echo "🌐 Step 2: Cleaning up Application Load Balancers..."
ALB_ARNS=$(aws elbv2 describe-load-balancers --region "$REGION" \
  --query "LoadBalancers[?contains(LoadBalancerName, 'k8s-gymdev') || contains(LoadBalancerName, 'apigatew') || contains(LoadBalancerName, 'gym')].LoadBalancerArn" \
  --output text 2>/dev/null || true)

if [ -n "$ALB_ARNS" ]; then
  for alb_arn in $ALB_ARNS; do
    echo "  -> Deleting Load Balancer: $alb_arn"
    aws elbv2 delete-load-balancer --load-balancer-arn "$alb_arn" --region "$REGION"
  done
  echo "     Waiting 45 seconds for AWS to release Load Balancer ENIs..."
  sleep 45
fi

# 3. Clean up Target Groups
TG_ARNS=$(aws elbv2 describe-target-groups --region "$REGION" \
  --query "TargetGroups[?contains(TargetGroupName, 'k8s-gymdev') || contains(TargetGroupName, 'api-gateway') || contains(TargetGroupName, 'gym')].TargetGroupArn" \
  --output text 2>/dev/null || true)

if [ -n "$TG_ARNS" ]; then
  for tg in $TG_ARNS; do
    aws elbv2 delete-target-group --target-group-arn "$tg" --region "$REGION" 2>/dev/null || true
  done
fi

echo "✓ Pre-destroy cleanup completed successfully."