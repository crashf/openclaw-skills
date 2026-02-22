#!/usr/bin/env bash
# Search/list NinjaRMM devices
# Usage: devices.sh [--org ORG_ID] [--search NAME] [--offline] [--limit N]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get credentials from openclaw.json
NINJA_CLIENT_ID=$(jq -r '.skills.entries["ninja-rmm"].env.NINJA_CLIENT_ID' ~/.openclaw/openclaw.json)
NINJA_CLIENT_SECRET=$(jq -r '.skills.entries["ninja-rmm"].env.NINJA_CLIENT_SECRET' ~/.openclaw/openclaw.json)
NINJA_INSTANCE=$(jq -r '.skills.entries["ninja-rmm"].env.NINJA_INSTANCE // "app.ninjarmm.com"' ~/.openclaw/openclaw.json)

export NINJA_CLIENT_ID NINJA_CLIENT_SECRET NINJA_INSTANCE

# Get token
TOKEN=$("$SCRIPT_DIR/auth.sh")

# Parse args
ORG_ID=""
SEARCH=""
OFFLINE_ONLY="false"
LIMIT=50

while [[ $# -gt 0 ]]; do
  case $1 in
    --org) ORG_ID="$2"; shift 2 ;;
    --search) SEARCH="$2"; shift 2 ;;
    --offline) OFFLINE_ONLY="true"; shift ;;
    --limit) LIMIT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Build URL with optional org filter
URL="https://${NINJA_INSTANCE}/v2/devices"
if [[ -n "$ORG_ID" ]]; then
  URL="https://${NINJA_INSTANCE}/v2/organization/${ORG_ID}/devices"
fi

# Fetch devices
DEVICES=$(curl -s -H "Authorization: Bearer $TOKEN" "$URL")

# Filter and format
echo "$DEVICES" | jq -r --arg search "$SEARCH" --arg offline "$OFFLINE_ONLY" --argjson limit "$LIMIT" '
  [.[]
    | select($search == "" or (.systemName // "" | ascii_downcase | contains($search | ascii_downcase)))
    | select($offline == "false" or .offline == true)
  ][:$limit][]
  | "\(if .offline then "🔴" else "🟢" end) \(.systemName // "Unknown") | \(.nodeClass // "?") | Org \(.organizationId) | ID \(.id)"
'
