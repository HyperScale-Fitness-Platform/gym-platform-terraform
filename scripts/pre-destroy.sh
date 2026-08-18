#!/usr/bin/env bash

# Do NOT use set -e blindly when cleaning up dynamic AWS resources
# We want the cleanup to attempt all deletions even if one fails
set -u

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
ENV_NAME="${1:-dev}"
ECR_REPOS=("gym-api-gateway" "gym-auth-service")

echo "🚀 Starting Pre-Destroy Cleanup Script for environment: [${ENV_NAME}] in [${REGION}]..."

# ------------------------------------------------------------------
# 1. Purge ECR Images
# ------------------------------------------------------------------
echo "📦 Step 1: Cleaning up ECR Repositories..."
for repo in "${ECR_REPOS[@]}"; do
  if aws ecr describe-repositories --region "$REGION" --repository-names "$repo" >/dev/null 2>&1; then
    IMAGES=$(aws ecr list-images --region "$REGION" --repository-name "$repo" --query 'imageIds[*]' --output json 2>/dev/null || echo "[]")
    if [ "$IMAGES" != "[]" ] && [ -n "$IMAGES" ]; then
      echo "  -> Purging images from $repo..."
      aws ecr batch-delete-image --region "$REGION" --repository-name "$repo" --image-ids "$IMAGES" >/dev/null 2>&1 || true
      echo "     ✓ Images deleted from $repo."
    else
      echo "     ✓ $repo is already empty."
    fi
  fi
done

# ------------------------------------------------------------------
# 2. Clean Up Application Load Balancers & Target Groups
# ------------------------------------------------------------------
echo "🌐 Step 2: Cleaning up Application Load Balancers..."
ALB_ARNS=$(aws elbv2 describe-load-balancers --region "$REGION" \
  --query "LoadBalancers[?contains(LoadBalancerName, 'gym') || contains(LoadBalancerName, 'apigatew')].LoadBalancerArn" \
  --output text 2>/dev/null || true)

if [ -n "$ALB_ARNS" ]; then
  for alb_arn in $ALB_ARNS; do
    echo "  -> Deleting Load Balancer: $alb_arn"
    aws elbv2 delete-load-balancer --load-balancer-arn "$alb_arn" --region "$REGION" 2>/dev/null || true
  done
  echo "     Waiting 45 seconds for ALB ENIs to enter detaching state..."
  sleep 45
else
  echo "     ✓ No active ALBs found."
fi

# Clean Target Groups
TG_ARNS=$(aws elbv2 describe-target-groups --region "$REGION" \
  --query "TargetGroups[?contains(TargetGroupName, 'gym') || contains(TargetGroupName, 'api-gateway')].TargetGroupArn" \
  --output text 2>/dev/null || true)

if [ -n "$TG_ARNS" ]; then
  for tg in $TG_ARNS; do
    aws elbv2 delete-target-group --target-group-arn "$tg" --region "$REGION" 2>/dev/null || true
  done
  echo "     ✓ Target Groups deleted."
fi

# ------------------------------------------------------------------
# 3. Dynamic VPC Discovery & Cleanup (ENIs & Security Groups)
# ------------------------------------------------------------------
echo "🧹 Step 3: Checking for lingering VPC resources..."

VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" \
  --filters "Name=tag:Project,Values=gym-platform" "Name=tag:Environment,Values=${ENV_NAME}" \
  --query "Vpcs[0].VpcId" --output text 2>/dev/null || true)

# Fallback VPC search by tag Name if Project tag is not found
if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ] || [ "$VPC_ID" = "null" ]; then
  VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" \
    --filters "Name=tag:Name,Values=*gym-vpc-${ENV_NAME}*" \
    --query "Vpcs[0].VpcId" --output text 2>/dev/null || true)
fi

if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ] && [ "$VPC_ID" != "null" ]; then
  echo "  -> Target VPC identified: $VPC_ID"

  # A. Detach and Delete Lingering Network Interfaces (ENIs)
  echo "  -> Cleaning lingering ENIs..."
  ENIS=$(aws ec2 describe-network-interfaces --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "NetworkInterfaces[*].NetworkInterfaceId" --output text 2>/dev/null || true)

  if [ -n "$ENIS" ]; then
    for eni in $ENIS; do
      ATTACH_ID=$(aws ec2 describe-network-interfaces --region "$REGION" \
        --network-interface-ids "$eni" \
        --query "NetworkInterfaces[0].Attachment.AttachmentId" --output text 2>/dev/null || true)

      if [ -n "$ATTACH_ID" ] && [ "$ATTACH_ID" != "None" ] && [ "$ATTACH_ID" != "null" ]; then
        echo "     Detaching ENI: $eni (Attachment: $ATTACH_ID)..."
        aws ec2 detach-network-interface --region "$REGION" --attachment-id "$ATTACH_ID" --force 2>/dev/null || true
        sleep 2
      fi

      echo "     Deleting ENI: $eni..."
      aws ec2 delete-network-interface --region "$REGION" --network-interface-id "$eni" 2>/dev/null || true
    done
  else
    echo "     ✓ No dangling ENIs found."
  fi

  # B. Strip Rules & Delete Non-Default Security Groups
  echo "  -> Cleaning non-default Security Groups..."
  SGS=$(aws ec2 describe-security-groups --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "SecurityGroups[?GroupName!='default'].GroupId" --output text 2>/dev/null || true)

  if [ -n "$SGS" ]; then
    # Pass 1: Revoke all rules to avoid circular dependency locks
    for sg in $SGS; do
      aws ec2 revoke-security-group-ingress --region "$REGION" --group-id "$sg" --protocol all --cidr 0.0.0.0/0 2>/dev/null || true
      aws ec2 revoke-security-group-egress --region "$REGION" --group-id "$sg" --protocol all --cidr 0.0.0.0/0 2>/dev/null || true
    done

    # Pass 2: Delete the security groups
    for sg in $SGS; do
      echo "     Deleting Security Group: $sg..."
      aws ec2 delete-security-group --region "$REGION" --group-id "$sg" 2>/dev/null || true
    done
  else
    echo "     ✓ No non-default Security Groups found."
  fi
else
  echo "  ✓ No target VPC found or already deleted."
fi

echo "=========================================================="
echo "  ✓ Pre-destroy cleanup completed successfully."
echo "=========================================================="