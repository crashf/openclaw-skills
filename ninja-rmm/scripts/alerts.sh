#!/usr/bin/env bash
# List active NinjaRMM alerts
# Usage: alerts.sh [--severity critical|moderate|minor] [--org ORG_ID] [--limit N]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source ~/.openclaw/openclaw.json 2>/dev/null || true

# Get credentials from openclaw.json
NINJA_CLIENT_ID=$(jq -r '.skills.entries["ninja-rmm"].env.NINJA_CLIENT_ID' ~/.openclaw/openclaw.json)
NINJA_CLIENT_SECRET=$(jq -r '.skills.entries["ninja-rmm"].env.NINJA_CLIENT_SECRET' ~/.openclaw/openclaw.json)
NINJA_INSTANCE=$(jq -r '.skills.entries["ninja-rmm"].env.NINJA_INSTANCE // "app.ninjarmm.com"' ~/.openclaw/openclaw.json)

export NINJA_CLIENT_ID NINJA_CLIENT_SECRET NINJA_INSTANCE

# Get token
TOKEN=$("$SCRIPT_DIR/auth.sh")

# Parse args
SEVERITY=""
ORG_ID=""
LIMIT=20

while [[ $# -gt 0 ]]; do
  case $1 in
    --severity) SEVERITY="$2"; shift 2 ;;
    --org) ORG_ID="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Fetch alerts
ALERTS=$(curl -s -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/alerts")

# Filter and format
echo "$ALERTS" | jq -r --arg sev "$SEVERITY" --arg org "$ORG_ID" --argjson limit "$LIMIT" '
  [.[] 
    | select($sev == "" or (.severity // "" | ascii_downcase) == ($sev | ascii_downcase))
    | select($org == "" or (.organizationId | tostring) == $org)
  ][:$limit][]
  | "\(.severity // "UNKNOWN") | Org \(.organizationId) | Device \(.deviceId) | \(.message // .sourceType)"
'
