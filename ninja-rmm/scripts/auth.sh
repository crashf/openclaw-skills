#!/usr/bin/env bash
# NinjaRMM OAuth2 Authentication
# Caches token to avoid repeated auth calls

set -euo pipefail

CACHE_FILE="${HOME}/.cache/ninja-rmm-token.json"
CACHE_DIR=$(dirname "$CACHE_FILE")

# Ensure cache directory exists
mkdir -p "$CACHE_DIR"

# Check for required env vars
: "${NINJA_CLIENT_ID:?Set NINJA_CLIENT_ID}"
: "${NINJA_CLIENT_SECRET:?Set NINJA_CLIENT_SECRET}"
: "${NINJA_INSTANCE:=app.ninjarmm.com}"

# Check if cached token is still valid
if [[ -f "$CACHE_FILE" ]]; then
  EXPIRES_AT=$(jq -r '.expires_at // 0' "$CACHE_FILE" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  if (( EXPIRES_AT > NOW + 60 )); then
    # Token still valid (with 60s buffer)
    jq -r '.access_token' "$CACHE_FILE"
    exit 0
  fi
fi

# Get new token
RESPONSE=$(curl -s -X POST "https://${NINJA_INSTANCE}/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=${NINJA_CLIENT_ID}&client_secret=${NINJA_CLIENT_SECRET}&scope=monitoring%20management")

# Check for error
if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
  echo "Auth failed: $(echo "$RESPONSE" | jq -r '.error_description // .error')" >&2
  exit 1
fi

# Calculate expiry and cache
ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r '.access_token')
EXPIRES_IN=$(echo "$RESPONSE" | jq -r '.expires_in // 3600')
EXPIRES_AT=$(($(date +%s) + EXPIRES_IN))

jq -n --arg token "$ACCESS_TOKEN" --argjson expires "$EXPIRES_AT" \
  '{access_token: $token, expires_at: $expires}' > "$CACHE_FILE"

echo "$ACCESS_TOKEN"
