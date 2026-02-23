#!/usr/bin/env bash
# Full cert lifecycle: renew + distribute to all servers
# Usage: full-renewal.sh [--force] [--staging] [--dry-run]
#
# This is what you'd schedule as a cron job (monthly or every 60 days)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FORCE=""
STAGING=""
DRY_RUN=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --force) FORCE="--force"; shift ;;
    --staging) STAGING="--staging"; shift ;;
    --dry-run) DRY_RUN="--dry-run"; shift ;;
    *) shift ;;
  esac
done

echo "╔══════════════════════════════════════════╗"
echo "║  Pund-IT Wildcard Certificate Manager    ║"
echo "║  *.pund-it.ca                            ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# Step 1: Renew
echo "━━━ Step 1: Certificate Renewal ━━━"
if [[ -z "$DRY_RUN" ]]; then
  bash "$SCRIPT_DIR/renew-cert.sh" $FORCE $STAGING
else
  echo "[DRY RUN] Would run: renew-cert.sh $FORCE $STAGING"
fi
echo ""

# Step 2: Distribute
echo "━━━ Step 2: Distribution ━━━"
bash "$SCRIPT_DIR/distribute-cert.sh" $DRY_RUN
echo ""

echo "╔══════════════════════════════════════════╗"
echo "║  ✅ Certificate lifecycle complete        ║"
echo "╚══════════════════════════════════════════╝"
