#!/usr/bin/env bash
# Monitor maintenance window progress for an organization
# Usage: maintenance-monitor.sh --org ORG_ID [--phase scan|patch|reboot|final] [--notify]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get credentials
NINJA_CLIENT_ID=$(jq -r '.skills.entries["ninja-rmm"].env.NINJA_CLIENT_ID' ~/.openclaw/openclaw.json)
NINJA_CLIENT_SECRET=$(jq -r '.skills.entries["ninja-rmm"].env.NINJA_CLIENT_SECRET' ~/.openclaw/openclaw.json)
NINJA_INSTANCE=$(jq -r '.skills.entries["ninja-rmm"].env.NINJA_INSTANCE // "app.ninjarmm.com"' ~/.openclaw/openclaw.json)

# Get token
get_token() {
  curl -s -X POST "https://${NINJA_INSTANCE}/oauth/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials&client_id=${NINJA_CLIENT_ID}&client_secret=${NINJA_CLIENT_SECRET}&scope=monitoring" \
    | jq -r '.access_token'
}

# Parse arguments
ORG_ID=""
PHASE="status"
NOTIFY="false"
WINDOW_START=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --org) ORG_ID="$2"; shift 2 ;;
    --phase) PHASE="$2"; shift 2 ;;
    --notify) NOTIFY="true"; shift ;;
    --window-start) WINDOW_START="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$ORG_ID" ]]; then
  echo "Usage: maintenance-monitor.sh --org ORG_ID [--phase scan|patch|reboot|final] [--notify]"
  exit 1
fi

TOKEN=$(get_token)

# Get org name
ORG_NAME=$(curl -s -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/organization/${ORG_ID}" | jq -r '.name // "Unknown"')

# Get Windows devices only (servers + workstations)
DEVICES=$(curl -s -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/organization/${ORG_ID}/devices" \
  | jq '[.[] | select(.nodeClass == "WINDOWS_SERVER" or .nodeClass == "WINDOWS_WORKSTATION")]')

DEVICE_COUNT=$(echo "$DEVICES" | jq 'length')

if [[ "$DEVICE_COUNT" -eq 0 ]]; then
  echo "No Windows devices found for org $ORG_ID"
  exit 0
fi

# Calculate window start timestamp (default: 2 hours ago if not specified)
if [[ -z "$WINDOW_START" ]]; then
  WINDOW_START_TS=$(($(date +%s) - 7200))
else
  WINDOW_START_TS=$(date -d "$WINDOW_START" +%s 2>/dev/null || echo "$WINDOW_START")
fi

echo "=== Maintenance Monitor: $ORG_NAME (Org $ORG_ID) ==="
echo "Phase: $PHASE"
echo "Windows devices: $DEVICE_COUNT"
echo "Window start: $(date -d "@$WINDOW_START_TS" '+%Y-%m-%d %H:%M' 2>/dev/null || echo $WINDOW_START_TS)"
echo ""

# Track status
ONLINE=0
OFFLINE=0
REBOOTED=0
PENDING_PATCHES=0
FAILED_PATCHES=0
ISSUES=()

# Check each device
echo "$DEVICES" | jq -c '.[]' | while read -r device; do
  DEVICE_ID=$(echo "$device" | jq -r '.id')
  DEVICE_NAME=$(echo "$device" | jq -r '.systemName // "Unknown"')
  DEVICE_CLASS=$(echo "$device" | jq -r '.nodeClass')
  IS_OFFLINE=$(echo "$device" | jq -r '.offline')
  
  # Get detailed device info for last boot
  DEVICE_DETAIL=$(curl -s -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/device/${DEVICE_ID}")
  LAST_BOOT=$(echo "$DEVICE_DETAIL" | jq -r '.system.lastBoot // 0')
  LAST_BOOT_TS=$((LAST_BOOT / 1000))  # Convert from milliseconds
  
  # Check if rebooted since window start
  REBOOTED_SINCE="N"
  if [[ "$LAST_BOOT_TS" -gt "$WINDOW_START_TS" ]]; then
    REBOOTED_SINCE="Y"
  fi
  
  # Get patch status
  PATCHES=$(curl -s -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/device/${DEVICE_ID}/os-patches")
  PENDING=$(echo "$PATCHES" | jq '[.[] | select(.status == "PENDING" or .status == "APPROVED")] | length')
  FAILED=$(echo "$PATCHES" | jq '[.[] | select(.status == "FAILED")] | length')
  INSTALLED_TODAY=$(echo "$PATCHES" | jq --argjson start "$WINDOW_START_TS" '[.[] | select(.status == "INSTALLED" and (.installedAt // 0) > $start)] | length')
  
  # Status emoji
  if [[ "$IS_OFFLINE" == "true" ]]; then
    STATUS="🔴 OFFLINE"
  elif [[ "$REBOOTED_SINCE" == "Y" ]]; then
    STATUS="✅ REBOOTED"
  elif [[ "$INSTALLED_TODAY" -gt 0 ]]; then
    STATUS="🔄 PATCHED ($INSTALLED_TODAY)"
  elif [[ "$PENDING" -gt 0 ]]; then
    STATUS="⏳ PENDING ($PENDING)"
  else
    STATUS="🟢 ONLINE"
  fi
  
  # Add issues
  if [[ "$FAILED" -gt 0 ]]; then
    STATUS="$STATUS ⚠️ $FAILED FAILED"
  fi
  
  echo "$STATUS | $DEVICE_NAME ($DEVICE_CLASS)"
done

echo ""
echo "=== Summary ==="

# Re-aggregate for summary (the loop above runs in subshell)
SUMMARY=$(echo "$DEVICES" | jq -c '.[]' | while read -r device; do
  DEVICE_ID=$(echo "$device" | jq -r '.id')
  IS_OFFLINE=$(echo "$device" | jq -r '.offline')
  
  DEVICE_DETAIL=$(curl -s -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/device/${DEVICE_ID}")
  LAST_BOOT=$(echo "$DEVICE_DETAIL" | jq -r '.system.lastBoot // 0')
  LAST_BOOT_TS=$((LAST_BOOT / 1000))
  
  REBOOTED=0
  if [[ "$LAST_BOOT_TS" -gt "$WINDOW_START_TS" ]]; then
    REBOOTED=1
  fi
  
  PATCHES=$(curl -s -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/device/${DEVICE_ID}/os-patches")
  PENDING=$(echo "$PATCHES" | jq '[.[] | select(.status == "PENDING" or .status == "APPROVED")] | length')
  FAILED=$(echo "$PATCHES" | jq '[.[] | select(.status == "FAILED")] | length')
  
  echo "{\"offline\": $IS_OFFLINE, \"rebooted\": $REBOOTED, \"pending\": $PENDING, \"failed\": $FAILED}"
done | jq -s '{
  total: length,
  offline: [.[] | select(.offline == true)] | length,
  online: [.[] | select(.offline == false)] | length,
  rebooted: [.[] | select(.rebooted == 1)] | length,
  pending: ([.[] | .pending] | add),
  failed: ([.[] | .failed] | add)
}')

echo "$SUMMARY" | jq -r '"Devices: \(.total) total, \(.online) online, \(.offline) offline"'
echo "$SUMMARY" | jq -r '"Rebooted since window: \(.rebooted)/\(.total)"'
echo "$SUMMARY" | jq -r '"Pending patches: \(.pending // 0)"'
echo "$SUMMARY" | jq -r '"Failed patches: \(.failed // 0)"'

# Determine overall status
FAILED_COUNT=$(echo "$SUMMARY" | jq '.failed // 0')
OFFLINE_COUNT=$(echo "$SUMMARY" | jq '.offline')
REBOOTED_COUNT=$(echo "$SUMMARY" | jq '.rebooted')
TOTAL_COUNT=$(echo "$SUMMARY" | jq '.total')

if [[ "$FAILED_COUNT" -gt 0 ]]; then
  echo ""
  echo "⚠️  ISSUES DETECTED: $FAILED_COUNT failed patches"
  EXIT_CODE=1
elif [[ "$PHASE" == "final" && "$REBOOTED_COUNT" -lt "$TOTAL_COUNT" ]]; then
  NOT_REBOOTED=$((TOTAL_COUNT - REBOOTED_COUNT))
  echo ""
  echo "⚠️  $NOT_REBOOTED device(s) did not reboot"
  EXIT_CODE=1
else
  echo ""
  echo "✅ Maintenance progressing normally"
  EXIT_CODE=0
fi

exit ${EXIT_CODE:-0}
