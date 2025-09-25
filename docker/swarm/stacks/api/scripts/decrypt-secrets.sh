#!/bin/bash
set -e

# API Stack Age Secret Decryption Script
# Decrypts age-encrypted secrets and sources environment variables

if [[ -z "$AGE_ENCRYPTED_ASC_SECRETS" || -z "$AGE_SECRET_KEY" ]]; then
  echo "ERROR: AGE_ENCRYPTED_ASC_SECRETS and AGE_SECRET_KEY environment variables are required"
  exit 1
fi

echo "Decrypting secrets using age..."

# Check if age is installed
if ! command -v age &> /dev/null; then
  echo "ERROR: age is not installed. Install with: brew install age (macOS) or apt-get install age (Ubuntu)"
  exit 1
fi

# Create temporary files
SECRETS_FILE=$(mktemp)
AGE_KEY_FILE=$(mktemp)
ENV_FILE=$(mktemp)
ENV_TMP_FILE=$(mktemp)

# Cleanup function
cleanup() {
  rm -f "$SECRETS_FILE" "$AGE_KEY_FILE" "$ENV_FILE" "$ENV_TMP_FILE"
}
trap cleanup EXIT

echo "Creating temporary files..."

# Write encrypted secrets and key to temporary files
echo "$AGE_ENCRYPTED_ASC_SECRETS" > "$SECRETS_FILE"
echo "$AGE_SECRET_KEY" > "$AGE_KEY_FILE"
chmod 600 "$AGE_KEY_FILE"

echo "Decrypting secrets..."

# Decrypt secrets
if ! age --identity "$AGE_KEY_FILE" --decrypt "$SECRETS_FILE" > "$ENV_FILE"; then
  echo "ERROR: Failed to decrypt secrets"
  exit 1
fi

echo "Cleaning up duplicate environment variables..."

# Clean duplicates from .env (keep last occurrence of each variable)
touch "$ENV_TMP_FILE"
while IFS= read -r line; do
  if [[ $line =~ ^[A-Za-z0-9_]+=.*$ ]]; then
    # Extract the key (part before the first =)
    key=${line%%=*}
    # Remove any previous line with this key
    sed -i.bak "/^${key}=/d" "$ENV_TMP_FILE" && rm -f "${ENV_TMP_FILE}.bak"
  fi
  # Append the current line
  echo "$line" >> "$ENV_TMP_FILE"
done < "$ENV_FILE"

echo "Adding deployment variables..."

# Add deployment variables if they exist
{
  [[ -n "$DEPLOYMENT_VERSION" ]] && echo "DEPLOYMENT_VERSION=$DEPLOYMENT_VERSION"
  [[ -n "$DEPLOYMENT_TLD" ]] && echo "DEPLOYMENT_TLD=$DEPLOYMENT_TLD" 
  [[ -n "$DEPLOYMENT_ENV" ]] && echo "DEPLOYMENT_ENV=$DEPLOYMENT_ENV"
  [[ -n "$FCC_API_LOG_LEVEL" ]] && echo "FCC_API_LOG_LEVEL=$FCC_API_LOG_LEVEL"
} >> "$ENV_TMP_FILE"

echo "Sourcing environment variables..."

# Source all variables from the cleaned file
while IFS='=' read -r key value; do
  if [[ -n "$key" && ! "$key" =~ ^# ]]; then
    export "${key}=${value}"
    echo "  $key"
  fi
done < "$ENV_TMP_FILE"

VAR_COUNT=$(grep -c '^[A-Za-z0-9_]=' "$ENV_TMP_FILE" || echo "0")
echo "Successfully decrypted and sourced $VAR_COUNT environment variables"

# Optional: Save to .env file for manual inspection
if [[ "$1" == "--save-env" ]]; then
  cp "$ENV_TMP_FILE" .env
  echo "Environment variables saved to .env file"
fi