#!/usr/bin/env bash
set -e

REGION="us-east-1"

# Discover every repository dynamically so this never drifts from the
# infrastructure/main.tf ECR module list.
read -r -a ECR_REPOS <<< "$(aws ecr describe-repositories --region "$REGION" \
  --query 'repositories[].repositoryName' --output text 2>/dev/null || true)"

echo "📦 Cleaning up ECR Repositories: ${ECR_REPOS[*]:-<none>}"
for repo in "${ECR_REPOS[@]}"; do
  if aws ecr describe-repositories --region "$REGION" --repository-names "$repo" >/dev/null 2>&1; then
    IMAGES=$(aws ecr list-images --region "$REGION" --repository-name "$repo" --query 'imageIds[*]' --output json 2>/dev/null || echo "[]")
    if [ "$IMAGES" != "[]" ] && [ -n "$IMAGES" ]; then
      echo "   Purging images from $repo..."
      aws ecr batch-delete-image --region "$REGION" --repository-name "$repo" --image-ids "$IMAGES" >/dev/null
    fi
  fi
done
echo "✓ ECR image purge complete."