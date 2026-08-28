#!/usr/bin/env bash
#
# Seed the per-service secrets that the gym-platform-gitops ExternalSecrets read
# from AWS Secrets Manager. Idempotent: a secret that already exists is left
# untouched (never overwritten), so it is safe to re-run.
#
# Run once after Layer 1 (infrastructure/) and BEFORE the gym-platform-gitops
# orchestrator syncs the ArgoCD root-app.
#
# Env:
#   ENV                    target environment segment (default: dev)
#   AWS_REGION             default: us-east-1
#   STRIPE_SECRET_KEY      real Stripe secret key   (default: sk_test_PLACEHOLDER)
#   STRIPE_WEBHOOK_SECRET  Stripe endpoint whsec_…  (default: whsec_PLACEHOLDER)
#   AUTH_JWT_SECRET        auth-service JWT signing secret (default: random 96 hex)
#   AI_LLM_API_KEY        ai-service LLM gateway Bearer token (default: PLACEHOLDER)
#
set -euo pipefail

ENV="${ENV:-dev}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
STRIPE_SECRET_KEY="${STRIPE_SECRET_KEY:-sk_test_PLACEHOLDER}"
STRIPE_WEBHOOK_SECRET="${STRIPE_WEBHOOK_SECRET:-whsec_PLACEHOLDER}"
AUTH_JWT_SECRET="${AUTH_JWT_SECRET:-$(openssl rand -hex 48)}"
AI_LLM_API_KEY="${AI_LLM_API_KEY:-PLACEHOLDER_replace_with_real_ITI_LLM_key}"

rand_pw() { openssl rand -hex 24; }

# Create the secret only if it does not already exist.
ensure_secret() {
  local name="$1" value="$2"
  if aws secretsmanager describe-secret --region "$AWS_REGION" --secret-id "$name" >/dev/null 2>&1; then
    echo "  = $name (exists, left as-is)"
  else
    aws secretsmanager create-secret --region "$AWS_REGION" \
      --name "$name" --secret-string "$value" >/dev/null
    echo "  + $name (created)"
  fi
}

# {"username":"<u>","password":"<random>"}
ensure_db() {
  ensure_secret "$1" "$(printf '{"username":"%s","password":"%s"}' "$2" "$(rand_pw)")"
}

echo "Seeding gym/${ENV}/* application secrets in ${AWS_REGION}..."

ensure_db  "gym/${ENV}/auth-db-credentials"        "auth"
ensure_db  "gym/${ENV}/operations-db-credentials"  "operations"
ensure_db  "gym/${ENV}/profile-db-credentials"     "profile"
ensure_db  "gym/${ENV}/progress-mongo-credentials" "progress"
ensure_db  "gym/${ENV}/catalog-postgres-credentials" "catalog"
ensure_db  "gym/${ENV}/order-postgres-credentials"   "order"
ensure_db  "gym/${ENV}/payment-postgres-credentials" "payment"
ensure_db  "gym/${ENV}/social-db-credentials"      "social"
ensure_db  "gym/${ENV}/ai-db-credentials"          "ai"

# auth-service JWT signing secret — consumed as a raw string (no property).
ensure_secret "gym/${ENV}/auth-service/jwt" "${AUTH_JWT_SECRET}"

# Stripe keys — {"secret_key":..., "webhook_secret":...}
ensure_secret "gym/${ENV}/payment-service/stripe" \
  "$(printf '{"secret_key":"%s","webhook_secret":"%s"}' "$STRIPE_SECRET_KEY" "$STRIPE_WEBHOOK_SECRET")"

# ai-service LLM gateway token — {"api_key":...}. Placeholder is fine to start;
# fill in the real key with put-secret-value, then force-sync the ExternalSecret
# and restart deploy/ai-service.
ensure_secret "gym/${ENV}/ai-service/llm" \
  "$(printf '{"api_key":"%s"}' "$AI_LLM_API_KEY")"

echo "Done. Verify: aws secretsmanager list-secrets --region ${AWS_REGION} \\"
echo "  --query \"SecretList[?starts_with(Name,'gym/${ENV}/')].Name\""
