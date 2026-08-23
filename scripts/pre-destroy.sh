#!/usr/bin/env bash

set -u

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
ENV_NAME="${1:-dev}"
CLUSTER_NAME="gym-cluster"
ECR_REPOS=("gym-api-gateway" "gym-auth-service")

echo "🚀 Starting Pre-Destroy Cleanup Script for environment: [${ENV_NAME}] in [${REGION}]..."

# ------------------------------------------------------------------
# 0. Gracefully Delete Kubernetes Ingress & LoadBalancer Services
# ------------------------------------------------------------------
echo "☸️  Step 0: Checking for live EKS cluster to delete Ingresses..."
if aws eks describe-cluster --region "$REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1; then
  echo "  -> Connected to cluster $CLUSTER_NAME. Deleting ingress resources..."
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1 || true
  kubectl delete ingress --all --all-namespaces --timeout=60s >/dev/null 2>&1 || true
  kubectl delete svc --all --all-namespaces --field-selector spec.type=LoadBalancer --timeout=60s >/dev/null 2>&1 || true
  echo "     ✓ Ingress resources cleaned from cluster."
  sleep 10
else
  echo "     ✓ Cluster not found or already deleted. Proceeding with AWS API cleanup."
fi

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
  --query "LoadBalancers[?contains(LoadBalancerName, 'gym') || contains(LoadBalancerName, 'apigatew') || contains(LoadBalancerName, 'k8s-')].LoadBalancerArn" \
  --output text 2>/dev/null || true)

if [ -n "$ALB_ARNS" ]; then
  for alb_arn in $ALB_ARNS; do
    echo "  -> Deleting Load Balancer: $alb_arn"
    aws elbv2 delete-load-balancer --load-balancer-arn "$alb_arn" --region "$REGION" 2>/dev/null || true
  done
  echo "     Waiting 30 seconds for ALB ENIs to release..."
  sleep 30
else
  echo "     ✓ No active ALBs found."
fi

# Clean Target Groups
TG_ARNS=$(aws elbv2 describe-target-groups --region "$REGION" \
  --query "TargetGroups[?contains(TargetGroupName, 'gym') || contains(TargetGroupName, 'api-gateway') || contains(TargetGroupName, 'k8s-')].TargetGroupArn" \
  --output text 2>/dev/null || true)

if [ -n "$TG_ARNS" ]; then
  for tg in $TG_ARNS; do
    aws elbv2 delete-target-group --target-group-arn "$tg" --region "$REGION" 2>/dev/null || true
  done
  echo "     ✓ Target Groups deleted."
fi

# ------------------------------------------------------------------
# 3. Dynamic VPC Discovery & Thorough ENI Cleanup
# ------------------------------------------------------------------
echo "🧹 Step 3: Checking for lingering VPC resources..."

VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" \
  --filters "Name=tag:Project,Values=gym-platform" "Name=tag:Environment,Values=${ENV_NAME}" \
  --query "Vpcs[0].VpcId" --output text 2>/dev/null || true)

if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ] || [ "$VPC_ID" = "null" ]; then
  VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" \
    --filters "Name=tag:Name,Values=*gym-vpc-${ENV_NAME}*" \
    --query "Vpcs[0].VpcId" --output text 2>/dev/null || true)
fi

if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ] && [ "$VPC_ID" != "null" ]; then
  echo "  -> Target VPC identified: $VPC_ID"

  # A. Force Detach and Delete ALL Lingering ENIs (Including K8s Pod CNI interfaces)
  echo "  -> Purging lingering ENIs in VPC $VPC_ID..."
  ENIS=$(aws ec2 describe-network-interfaces --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "NetworkInterfaces[*].NetworkInterfaceId" --output text 2>/dev/null || true)

  if [ -n "$ENIS" ]; then
    for eni in $ENIS; do
      ATTACH_ID=$(aws ec2 describe-network-interfaces --region "$REGION" \
        --network-interface-ids "$eni" \
        --query "NetworkInterfaces[0].Attachment.AttachmentId" --output text 2>/dev/null || true)

      if [ -n "$ATTACH_ID" ] && [ "$ATTACH_ID" != "None" ] && [ "$ATTACH_ID" != "null" ]; then
        echo "     Force detaching ENI: $eni..."
        aws ec2 detach-network-interface --region "$REGION" --attachment-id "$ATTACH_ID" --force 2>/dev/null || true
        sleep 2
      fi

      echo "     Deleting ENI: $eni..."
      aws ec2 delete-network-interface --region "$REGION" --network-interface-id "$eni" 2>/dev/null || true
    done
    echo "     ✓ ENI cleanup pass completed."
  else
    echo "     ✓ No dangling ENIs found."
  fi

  # B. Strip Rules & Delete Non-Default Security Groups
  echo "  -> Cleaning non-default Security Groups..."
  SGS=$(aws ec2 describe-security-groups --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "SecurityGroups[?GroupName!='default'].GroupId" --output text 2>/dev/null || true)

  if [ -n "$SGS" ]; then
    for sg in $SGS; do
      aws ec2 revoke-security-group-ingress --region "$REGION" --group-id "$sg" --protocol all --cidr 0.0.0.0/0 2>/dev/null || true
      aws ec2 revoke-security-group-egress --region "$REGION" --group-id "$sg" --protocol all --cidr 0.0.0.0/0 2>/dev/null || true
    done

    for sg in $SGS; do
      echo "     Deleting Security Group: $sg..."
      aws ec2 delete-security-group --region "$REGION" --group-id "$sg" 2>/dev/null || true
    done
  fi

  # C. Delete VPC Endpoints & NAT Gateways
  echo "  -> Checking VPC Endpoints & NAT Gateways..."
  ENDPOINTS=$(aws ec2 describe-vpc-endpoints --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "VpcEndpoints[*].VpcEndpointId" --output text 2>/dev/null || true)

  if [ -n "$ENDPOINTS" ]; then
    for ep in $ENDPOINTS; do
      echo "     Deleting VPC Endpoint: $ep..."
      aws ec2 delete-vpc-endpoints --region "$REGION" --vpc-endpoint-ids "$ep" 2>/dev/null || true
    done
  fi

  NAT_GWS=$(aws ec2 describe-nat-gateways --region "$REGION" \
    --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available,pending" \
    --query "NatGateways[*].NatGatewayId" --output text 2>/dev/null || true)

  if [ -n "$NAT_GWS" ]; then
    for nat in $NAT_GWS; do
      echo "     Deleting NAT Gateway: $nat..."
      aws ec2 delete-nat-gateway --region "$REGION" --nat-gateway-id "$nat" 2>/dev/null || true
    done
  fi
else
  echo "  ✓ No target VPC found or already deleted."
fi

echo "=========================================================="
echo "  ✓ Pre-destroy cleanup completed successfully."
echo "=========================================================="