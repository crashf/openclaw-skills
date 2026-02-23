#!/usr/bin/env bash
# Renew wildcard certificate using acme.sh + cPanel DNS API
# Usage: renew-cert.sh [--force] [--staging]
#
# Handles:
#   1. Issue/renew *.pund-it.ca via DNS-01 challenge
#   2. Export as PFX for Windows servers
#   3. Copy to distribution directory
#
# First run: Issues a new cert
# Subsequent runs: Renews if within 30 days of expiry (or --force)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/servers.json"
CERT_DIR="$SCRIPT_DIR/../certs"

# Parse config
DOMAIN=$(jq -r '.domain' "$CONFIG_FILE")
PFX_PASSWORD=$(jq -r '.pfxPassword' "$CONFIG_FILE")
CPANEL_HOST=$(jq -r '.cpanel.hostname' "$CONFIG_FILE")
CPANEL_PORT=$(jq -r '.cpanel.port' "$CONFIG_FILE")
CPANEL_USER=$(jq -r '.cpanel.username' "$CONFIG_FILE")
CPANEL_TOKEN=$(jq -r '.cpanel.apiToken' "$CONFIG_FILE")

# Strip wildcard for base domain
BASE_DOMAIN="${DOMAIN#\*.}"

# Parse args
FORCE="false"
STAGING=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --force) FORCE="true"; shift ;;
    --staging) STAGING="--staging"; shift ;;
    *) shift ;;
  esac
done

# Validate config
if [[ -z "$CPANEL_USER" || "$CPANEL_USER" == "null" || -z "$CPANEL_TOKEN" || "$CPANEL_TOKEN" == "null" ]]; then
  echo "❌ cPanel credentials not configured in config/servers.json"
  echo "   Set cpanel.username and cpanel.apiToken"
  exit 1
fi

# Check for acme.sh (build-time install now required)
ACME_HOME="${HOME}/.acme.sh"
if [[ ! -f "$ACME_HOME/acme.sh" ]]; then
  echo "\U1F534 acme.sh missing! This should be pre-installed in the Docker build."
  exit 1
fi

# Ensure cert output directory exists
mkdir -p "$CERT_DIR"

# Set cPanel DNS API credentials for acme.sh
export cPanel_Username="$CPANEL_USER"
export cPanel_Apitoken="$CPANEL_TOKEN"
export cPanel_Hostname="https://${CPANEL_HOST}:${CPANEL_PORT}"

echo "=== Wildcard Certificate Renewal ==="
echo "Domain: $DOMAIN"
echo "Base domain: $BASE_DOMAIN"
echo "cPanel: $CPANEL_HOST"
echo ""

# Check if cert exists and if renewal needed
FORCE_FLAG=""
if [[ "$FORCE" == "true" ]]; then
  FORCE_FLAG="--force"
  echo "🔄 Force renewal requested"
fi

# Issue or renew the certificate
echo "🔐 Requesting certificate via DNS-01 challenge..."
"$ACME_HOME/acme.sh" --issue \
  -d "$BASE_DOMAIN" \
  -d "$DOMAIN" \
  --dns dns_cpanel \
  --keylength 2048 \
  $STAGING \
  $FORCE_FLAG \
  || {
    EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 2 ]]; then
      echo "ℹ️  Certificate is still valid, skipping renewal (use --force to override)"
      # Still export/copy in case distribution is needed
    else
      echo "❌ Certificate issuance/renewal failed (exit code: $EXIT_CODE)"
      exit 1
    fi
  }

# Install/copy certs to our distribution directory
echo "📋 Exporting certificates..."
"$ACME_HOME/acme.sh" --install-cert \
  -d "$BASE_DOMAIN" \
  -d "$DOMAIN" \
  --cert-file "$CERT_DIR/cert.pem" \
  --key-file "$CERT_DIR/key.pem" \
  --fullchain-file "$CERT_DIR/fullchain.pem" \
  --ca-file "$CERT_DIR/ca.pem"

# Generate PFX for Windows servers
echo "📦 Generating PFX..."
openssl pkcs12 -export \
  -out "$CERT_DIR/wildcard.pfx" \
  -inkey "$CERT_DIR/key.pem" \
  -in "$CERT_DIR/fullchain.pem" \
  -passout "pass:${PFX_PASSWORD}"

# Also generate a base64-encoded PFX for easy transfer
base64 "$CERT_DIR/wildcard.pfx" > "$CERT_DIR/wildcard.pfx.b64"

# Generate cert info file
echo "📄 Generating cert info..."
openssl x509 -in "$CERT_DIR/cert.pem" -noout -subject -issuer -dates -fingerprint -sha256 > "$CERT_DIR/cert-info.txt"
THUMBPRINT=$(openssl x509 -in "$CERT_DIR/cert.pem" -noout -fingerprint -sha1 | sed 's/.*=//;s/://g')
echo "Thumbprint (SHA1): $THUMBPRINT" >> "$CERT_DIR/cert-info.txt"
echo "$THUMBPRINT" > "$CERT_DIR/thumbprint.txt"

# Write metadata
EXPIRY=$(openssl x509 -in "$CERT_DIR/cert.pem" -noout -enddate | sed 's/notAfter=//')
jq -n \
  --arg domain "$DOMAIN" \
  --arg thumbprint "$THUMBPRINT" \
  --arg expiry "$EXPIRY" \
  --arg renewed "$(date -Iseconds)" \
  --arg pfxPassword "$PFX_PASSWORD" \
  '{domain: $domain, thumbprint: $thumbprint, expiry: $expiry, renewed: $renewed, pfxPassword: $pfxPassword}' \
  > "$CERT_DIR/metadata.json"

echo ""
echo "✅ Certificate ready!"
echo "   Domain: $DOMAIN"
echo "   Thumbprint: $THUMBPRINT"
echo "   Expires: $EXPIRY"
echo "   PFX: $CERT_DIR/wildcard.pfx"
echo ""
echo "Next: Run distribute-cert.sh to push to servers"
