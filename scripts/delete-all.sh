#!/usr/bin/env bash
set -euo pipefail

REGION="us-east-1"
CLUSTER="gym-cluster"

echo "=== 1. Deleting EKS Cluster ==="
aws eks delete-cluster --name "$CLUSTER" --region "$REGION" 2>/dev/null || true
echo "Waiting for EKS Cluster deletion (this takes ~10-15 mins)..."
aws eks wait cluster-deleted --name "$CLUSTER" --region "$REGION" 2>/dev/null || true
echo "  ✓ EKS cluster deleted."

echo "=== 2. Deleting NAT Gateways ==="
NAT_IDS=$(aws ec2 describe-nat-gateways --region "$REGION" \
  --filter "Name=state,Values=pending,available" \
  --query "NatGateways[*].NatGatewayId" --output text)

for nat in $NAT_IDS; do
  if [ -n "$nat" ] && [ "$nat" != "None" ]; then
    echo "Deleting NAT Gateway: $nat"
    aws ec2 delete-nat-gateway --nat-gateway-id "$nat" --region "$REGION"
  fi
done

if [ -n "$NAT_IDS" ]; then
  echo "Waiting for NAT Gateways to fully terminate..."
  sleep 60
fi

echo "=== 3. Releasing Unattached Elastic IPs ==="
# Release unattached EIPs to stop hourly idle charges
EIP_ALLOCS=$(aws ec2 describe-addresses --region "$REGION" \
  --query "Addresses[?AssociationId==null].AllocationId" --output text)

for alloc in $EIP_ALLOCS; do
  if [ -n "$alloc" ] && [ "$alloc" != "None" ]; then
    echo "Releasing EIP allocation: $alloc"
    aws ec2 release-address --allocation-id "$alloc" --region "$REGION" 2>/dev/null || true
  fi
done

echo "=== 4. Deleting Custom VPCs & Dependencies ==="
CUSTOM_VPCS=$(aws ec2 describe-vpcs --region "$REGION" \
  --filters "Name=isDefault,Values=false" \
  --query "Vpcs[*].VpcId" --output text)

for vpc in $CUSTOM_VPCS; do
  if [ -n "$vpc" ] && [ "$vpc" != "None" ]; then
    echo "Cleaning up VPC: $vpc"

    # Detach & Delete Internet Gateways
    IGWS=$(aws ec2 describe-internet-gateways --region "$REGION" \
      --filters "Name=attachment.vpc-id,Values=$vpc" \
      --query "InternetGateways[*].InternetGatewayId" --output text)
    for igw in $IGWS; do
      aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc" --region "$REGION" 2>/dev/null || true
      aws ec2 delete-internet-gateway --internet-gateway-id "$igw" --region "$REGION" 2>/dev/null || true
    done

    # Delete Security Groups (except default)
    SGS=$(aws ec2 describe-security-groups --region "$REGION" \
      --filters "Name=vpc-id,Values=$vpc" \
      --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
    for sg in $SGS; do
      aws ec2 delete-security-group --group-id "$sg" --region "$REGION" 2>/dev/null || true
    done

    # Delete Subnets
    SUBNETS=$(aws ec2 describe-subnets --region "$REGION" \
      --filters "Name=vpc-id,Values=$vpc" \
      --query "Subnets[*].SubnetId" --output text)
    for sub in $SUBNETS; do
      aws ec2 delete-subnet --subnet-id "$sub" --region "$REGION" 2>/dev/null || true
    done

    # Delete Custom Route Tables
    RTBS=$(aws ec2 describe-route-tables --region "$REGION" \
      --filters "Name=vpc-id,Values=$vpc" \
      --query "RouteTables[?Associations[0].Main!=\`true\`].RouteTableId" --output text)
    for rtb in $RTBS; do
      aws ec2 delete-route-table --route-table-id "$rtb" --region "$REGION" 2>/dev/null || true
    done

    # Delete VPC
    aws ec2 delete-vpc --vpc-id "$vpc" --region "$REGION" 2>/dev/null || true
    echo "  ✓ VPC $vpc deleted."
  fi
done

echo "=== 5. Deleting CloudWatch Logs & KMS Aliases ==="
aws logs delete-log-group --log-group-name "/aws/eks/$CLUSTER/cluster" --region "$REGION" 2>/dev/null || true
aws kms delete-alias --alias-name "alias/eks/$CLUSTER" --region "$REGION" 2>/dev/null || true

echo "=== Cleanup Complete ==="
