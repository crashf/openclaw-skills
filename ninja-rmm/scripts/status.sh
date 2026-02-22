#!/usr/bin/env bash
# NinjaRMM quick status overview
# Usage: status.sh [--org ORG_ID]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get credentials from openclaw.json
NINJA_CLIENT_ID=$(jq -r '.skills.entries["ninja-rmm"].env.NINJA_CLIENT_ID' ~/.openclaw/openclaw.json)
NINJA_CLIENT_SECRET=$(jq -r '.skills.entries["ninja-rmm"].env.NINJA_CLIENT_SECRET' ~/.openclaw/openclaw.json)
NINJA_INSTANCE=$(jq -r '.skills.entries["ninja-rmm"].env.NINJA_INSTANCE // "app.ninjarmm.com"' ~/.openclaw/openclaw.json)

export NINJA_CLIENT_ID NINJA_CLIENT_SECRET NINJA_INSTANCE

# Get token
TOKEN=$("$SCRIPT_DIR/auth.sh")

ORG_ID=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --org) ORG_ID="$2"; shift 2 ;;
    *) shift ;;
  esac
done

echo "=== NinjaRMM Status ==="
echo ""

# Organizations
if [[ -z "$ORG_ID" ]]; then
  ORGS=$(curl -s -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/organizations")
  ORG_COUNT=$(echo "$ORGS" | jq 'length')
  echo "Organizations: $ORG_COUNT"
fi

# Devices
if [[ -n "$ORG_ID" ]]; then
  DEVICES=$(curl -s -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/organization/${ORG_ID}/devices")
else
  DEVICES=$(curl -s -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/devices")
fi
DEVICE_COUNT=$(echo "$DEVICES" | jq 'length')
OFFLINE_COUNT=$(echo "$DEVICES" | jq '[.[] | select(.offline == true)] | length')
ONLINE_COUNT=$((DEVICE_COUNT - OFFLINE_COUNT))

echo "Devices: $DEVICE_COUNT total ($ONLINE_COUNT online, $OFFLINE_COUNT offline)"

# Alerts
ALERTS=$(curl -s -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/alerts")
ALERT_COUNT=$(echo "$ALERTS" | jq 'length')
CRITICAL=$(echo "$ALERTS" | jq '[.[] | select(.severity == "CRITICAL")] | length')
MODERATE=$(echo "$ALERTS" | jq '[.[] | select(.severity == "MODERATE")] | length')

echo "Alerts: $ALERT_COUNT active ($CRITICAL critical, $MODERATE moderate)"

# Top alert types
if [[ "$ALERT_COUNT" -gt 0 ]]; then
  echo ""
  echo "Top alert types:"
  echo "$ALERTS" | jq -r '[.[] | .sourceType] | group_by(.) | map({type: .[0], count: length}) | sort_by(-.count)[:5][] | "  \(.count)x \(.type)"'
fi

# Stale reboots (30+ days)
echo ""
STALE_THRESHOLD=$(date -d "30 days ago" +%s 2>/dev/null || date -v-30d +%s)
STALE_COUNT=$(echo "$DEVICES" | jq --argjson thresh "$STALE_THRESHOLD" '
  [.[] | select(.lastRebootTimestamp != null and (.lastRebootTimestamp | . / 1000) < $thresh)] | length
')
echo "Devices needing reboot (30+ days): $STALE_COUNT"
