#!/bin/bash
set -e

# API Stack Environment Validation Script
# Validates all required environment variables are set

REQUIRED_VARS=(
  "DOCKER_REGISTRY"
  "MONGOHQ_URL" 
  "SENTRY_DSN"
  "SENTRY_ENVIRONMENT"
  "AUTH0_CLIENT_ID"
  "AUTH0_CLIENT_SECRET"
  "AUTH0_DOMAIN"
  "JWT_SECRET"
  "COOKIE_SECRET"
  "COOKIE_DOMAIN"
  "SES_ID"
  "SES_SECRET"
  "GROWTHBOOK_FASTIFY_API_HOST"
  "GROWTHBOOK_FASTIFY_CLIENT_KEY"
  "HOME_LOCATION"
  "API_LOCATION"
  "STRIPE_SECRET_KEY"
  "LOKI_URL"
  "DEPLOYMENT_VERSION"
  "DEPLOYMENT_TLD"
  "DEPLOYMENT_ENV"
  "FCC_API_LOG_LEVEL"
)

echo "Validating environment variables for API stack deployment..."

MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var}" ]]; then
    MISSING_VARS+=("$var")
  fi
done

if [[ ${#MISSING_VARS[@]} -gt 0 ]]; then
  echo "ERROR: The following required environment variables are missing or empty:"
  printf '  - %s\n' "${MISSING_VARS[@]}"
  echo ""
  echo "Use .env.sample as a reference for all required variables"
  exit 1
fi

echo "All required environment variables are set (${#REQUIRED_VARS[@]} variables checked)"

# Optional: Validate version format
if [[ ! "$DEPLOYMENT_VERSION" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "WARNING: DEPLOYMENT_VERSION format may be invalid: $DEPLOYMENT_VERSION"
fi

# Optional: Validate TLD
if [[ "$DEPLOYMENT_TLD" != "dev" && "$DEPLOYMENT_TLD" != "org" ]]; then
  echo "WARNING: DEPLOYMENT_TLD should be 'dev' or 'org', got: $DEPLOYMENT_TLD"
fi

echo "Environment validation passed - ready for deployment"