#!/usr/bin/env bash
# Distribute wildcard cert to all configured servers
# Usage: distribute-cert.sh [--server NAME] [--role veeam-cc|screenconnect] [--dry-run]
#
# Pull-based approach:
#   1. Copies PFX to each Windows server via SSH/SCP
#   2. Runs the appropriate PowerShell apply script remotely
#
# Requires: SSH access to Windows servers (OpenSSH) or smbclient

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/servers.json"
CERT_DIR="$SCRIPT_DIR/../certs"
PS_SCRIPTS="$SCRIPT_DIR/powershell"

# Parse args
TARGET_SERVER=""
TARGET_ROLE=""
DRY_RUN="false"
SSH_USER="administrator"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

while [[ $# -gt 0 ]]; do
  case $1 in
    --server) TARGET_SERVER="$2"; shift 2 ;;
    --role) TARGET_ROLE="$2"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    --user) SSH_USER="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Validate cert exists
if [[ ! -f "$CERT_DIR/wildcard.pfx" ]]; then
  echo "❌ No certificate found. Run renew-cert.sh first."
  exit 1
fi

# Load metadata
if [[ ! -f "$CERT_DIR/metadata.json" ]]; then
  echo "❌ No cert metadata found. Run renew-cert.sh first."
  exit 1
fi

THUMBPRINT=$(jq -r '.thumbprint' "$CERT_DIR/metadata.json")
PFX_PASSWORD=$(jq -r '.pfxPassword' "$CERT_DIR/metadata.json")
DOMAIN=$(jq -r '.domain' "$CERT_DIR/metadata.json")
EXPIRY=$(jq -r '.expiry' "$CERT_DIR/metadata.json")

echo "=== Certificate Distribution ==="
echo "Domain: $DOMAIN"
echo "Thumbprint: $THUMBPRINT"
echo "Expires: $EXPIRY"
echo "Dry run: $DRY_RUN"
echo ""

# Read servers from config
SERVERS=$(jq -c '.servers[] | select(.enabled == true)' "$CONFIG_FILE")

SUCCESS=0
FAILED=0
SKIPPED=0

while IFS= read -r server; do
  NAME=$(echo "$server" | jq -r '.name')
  IP=$(echo "$server" | jq -r '.ip')
  ROLES=$(echo "$server" | jq -r '.roles[]')
  
  # Filter by target server
  if [[ -n "$TARGET_SERVER" && "$NAME" != "$TARGET_SERVER" ]]; then
    continue
  fi
  
  # Filter by target role
  if [[ -n "$TARGET_ROLE" ]]; then
    if ! echo "$ROLES" | grep -q "$TARGET_ROLE"; then
      continue
    fi
  fi
  
  echo "━━━ $NAME ($IP) ━━━"
  echo "  Roles: $ROLES"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY RUN] Would distribute cert and apply for: $ROLES"
    SKIPPED=$((SKIPPED + 1))
    echo ""
    continue
  fi
  
  # Test connectivity
  if ! ssh $SSH_OPTS "$SSH_USER@$IP" "echo ok" &>/dev/null; then
    echo "  ❌ SSH connection failed to $SSH_USER@$IP"
    FAILED=$((FAILED + 1))
    echo ""
    continue
  fi
  
  # Create remote cert directory
  ssh $SSH_OPTS "$SSH_USER@$IP" "if not exist C:\\certs mkdir C:\\certs" 2>/dev/null || true
  
  # Copy PFX
  echo "  📦 Copying PFX..."
  scp $SSH_OPTS "$CERT_DIR/wildcard.pfx" "$SSH_USER@$IP:C:/certs/wildcard.pfx"
  
  # Apply for each role
  for role in $ROLES; do
    echo "  🔧 Applying for role: $role"
    
    case $role in
      veeam-cc)
        # Copy and run Veeam CC cert update script
        scp $SSH_OPTS "$PS_SCRIPTS/apply-veeam-cc.ps1" "$SSH_USER@$IP:C:/certs/apply-veeam-cc.ps1"
        ssh $SSH_OPTS "$SSH_USER@$IP" "powershell -ExecutionPolicy Bypass -File C:\\certs\\apply-veeam-cc.ps1 -PfxPath C:\\certs\\wildcard.pfx -PfxPassword '$PFX_PASSWORD' -Thumbprint '$THUMBPRINT'"
        ;;
      screenconnect)
        # Copy and run ScreenConnect cert update script
        scp $SSH_OPTS "$PS_SCRIPTS/apply-screenconnect.ps1" "$SSH_USER@$IP:C:/certs/apply-screenconnect.ps1"
        ssh $SSH_OPTS "$SSH_USER@$IP" "powershell -ExecutionPolicy Bypass -File C:\\certs\\apply-screenconnect.ps1 -PfxPath C:\\certs\\wildcard.pfx -PfxPassword '$PFX_PASSWORD' -Thumbprint '$THUMBPRINT'"
        ;;
      *)
        echo "  ⚠️  Unknown role: $role (skipped)"
        ;;
    esac
  done
  
  SUCCESS=$((SUCCESS + 1))
  echo "  ✅ Done"
  echo ""
done <<< "$SERVERS"

echo "=== Distribution Summary ==="
echo "Success: $SUCCESS | Failed: $FAILED | Skipped: $SKIPPED"

if [[ "$FAILED" -gt 0 ]]; then
  echo "⚠️  Some servers failed — check above for details"
  exit 1
fi

echo "✅ All servers updated"
