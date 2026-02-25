#!/usr/bin/env bash
# Monitor maintenance window progress for an organization (read-only)
# Usage: maintenance-monitor.sh --org ORG_ID [--phase scan|patch|reboot|final] [--window-start TIMESTAMP] [--link-base BASE]
# Example link base: https://pundit.rmmservice.com/#/deviceDashboard

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

ninja_load_creds
TOKEN=$(ninja_token)

ORG_ID=""
PHASE="status"
WINDOW_START=""
LINK_BASE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --org) ORG_ID="$2"; shift 2 ;;
    --phase) PHASE="$2"; shift 2 ;;
    --window-start) WINDOW_START="$2"; shift 2 ;;
    --link-base) LINK_BASE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# normalize link base (strip trailing slashes)
if [[ -n "$LINK_BASE" ]]; then
  LINK_BASE="${LINK_BASE%/}"
fi

if [[ -z "$ORG_ID" ]]; then
  echo "Usage: maintenance-monitor.sh --org ORG_ID [--phase scan|patch|reboot|final] [--window-start TIMESTAMP]"
  exit 1
fi

ORG_NAME=$(ninja_org_name "$TOKEN" "$ORG_ID")
ALL_DEVICES=$(ninja_fetch_all_devices "$TOKEN" "$ORG_ID")
DEVICES=$(echo "$ALL_DEVICES" | jq '[.[] | select(.nodeClass == "WINDOWS_SERVER")]')
DEVICE_COUNT=$(echo "$DEVICES" | jq 'length')

if [[ "$DEVICE_COUNT" -eq 0 ]]; then
  echo "No Windows servers found for $ORG_NAME (Org $ORG_ID)"
  exit 0
fi

if [[ -z "$WINDOW_START" ]]; then
  WINDOW_START_TS=$(($(date +%s) - 7200))
else
  WINDOW_START_TS=$(date -d "$WINDOW_START" +%s 2>/dev/null || echo "$WINDOW_START")
fi

TOTAL=0; ONLINE=0; OFFLINE=0; REBOOTED=0; PENDING_SUM=0; FAILED_SUM=0; PATCH_ERR_SUM=0; DL_ERR_SUM=0

echo "=== Maintenance Monitor: $ORG_NAME (Org $ORG_ID) ==="
echo "Phase: $PHASE"
echo "Windows servers: $DEVICE_COUNT"
echo "Window start: $(date -d "@$WINDOW_START_TS" '+%Y-%m-%d %H:%M' 2>/dev/null || echo $WINDOW_START_TS)"
echo ""

DEVICE_LIST=$(echo "$DEVICES" | jq -c '.[]')
while read -r device; do
  [[ -z "$device" ]] && continue
  DEVICE_ID=$(echo "$device" | jq -r '.id')
  DEVICE_NAME=$(echo "$device" | jq -r '.systemName // "Unknown"')
  DEVICE_CLASS=$(echo "$device" | jq -r '.nodeClass')
  IS_OFFLINE=$(echo "$device" | jq -r '.offline')

  # Device detail (for last boot)
  DEVICE_DETAIL=$(curl -s -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/device/${DEVICE_ID}")
  LAST_BOOT=$(echo "$DEVICE_DETAIL" | jq -r '.system.lastBoot // 0')
  LAST_BOOT_TS=$((LAST_BOOT / 1000))

  # OS patches (pending/failed)
  PATCHES=$(curl -s -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/device/${DEVICE_ID}/os-patches")
  PENDING=$(echo "$PATCHES" | jq '[.[] | select(.status == "PENDING" or .status == "APPROVED")] | length')
  FAILED=$(echo "$PATCHES" | jq '[.[] | select(.status == "FAILED")] | length')
  INSTALLED_TODAY=$(echo "$PATCHES" | jq --argjson start "$WINDOW_START_TS" '[.[] | select(.status == "INSTALLED" and (.installedAt // 0) > ($start*1000))] | length')

  # Activity log (authoritative for reboot/patch issues)
  ACTIVITIES=$(curl -s -g -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/device/${DEVICE_ID}/activities?pageSize=200")

  REBOOTED_SINCE=$(echo "$ACTIVITIES" | jq --argjson start "$WINDOW_START_TS" '[.activities[]? | select((.statusCode == "SYSTEM_REBOOTED" or (.message // "" | test("System rebooted";"i"))) and (.activityTime // 0) >= ($start))] | length')

  PATCH_ERRORS=$(echo "$ACTIVITIES" | jq '[.activities[]? | select(.activityType=="PATCH_MANAGEMENT") | select(
      (.activityResult == "FAILURE") or
      (.statusCode // "" | test("FAILED|ERROR";"i")) or
      (.message // "" | test("download error|failed|blocked";"i"))
    )] | length')

  POST_REBOOT_SCAN_REQ=$(echo "$ACTIVITIES" | jq '[.activities[]? | select(.message // "" | test("post reboot scan is required";"i"))] | length')

  # Also consider prior reboot detection (last boot) if activity missing
  REBOOTED_FLAG=$REBOOTED_SINCE
  if [[ "$REBOOTED_FLAG" -eq 0 && "$LAST_BOOT_TS" -gt "$WINDOW_START_TS" ]]; then
    REBOOTED_FLAG=1
  fi

  # Status string
  if [[ "$IS_OFFLINE" == "true" ]]; then
    STATUS="🔴 OFFLINE"
  elif [[ "$PATCH_ERRORS" -gt 0 ]]; then
    STATUS="⚠️ PATCH ISSUES ($PATCH_ERRORS)"
  elif [[ "$REBOOTED_FLAG" -gt 0 ]]; then
    STATUS="✅ REBOOTED"
  elif [[ "$INSTALLED_TODAY" -gt 0 ]]; then
    STATUS="🔄 PATCHED ($INSTALLED_TODAY)"
  elif [[ "$PENDING" -gt 0 ]]; then
    STATUS="⏳ PENDING ($PENDING)"
  else
    STATUS="🟢 ONLINE"
  fi

  if [[ "$FAILED" -gt 0 ]]; then
    STATUS="$STATUS ⚠️ $FAILED FAILED"
  fi

  echo "$STATUS | $DEVICE_NAME ($DEVICE_CLASS)"
  if [[ "$PATCH_ERRORS" -gt 0 ]]; then
    echo "  Notes: $PATCH_ERRORS patch issue(s) in activity log"
  fi
  if [[ "$POST_REBOOT_SCAN_REQ" -gt 0 ]]; then
    echo "  Notes: Post-reboot scan required to finalize patch results"
  fi
  if [[ -n "$LINK_BASE" ]]; then
    echo "  Link: ${LINK_BASE}/${DEVICE_ID}/overview"
  fi

  TOTAL=$((TOTAL+1))
  if [[ "$IS_OFFLINE" == "true" ]]; then OFFLINE=$((OFFLINE+1)); else ONLINE=$((ONLINE+1)); fi
  if [[ "$REBOOTED_FLAG" -gt 0 ]]; then REBOOTED=$((REBOOTED+1)); fi
  PENDING_SUM=$((PENDING_SUM + PENDING))
  FAILED_SUM=$((FAILED_SUM + FAILED))
  PATCH_ERR_SUM=$((PATCH_ERR_SUM + PATCH_ERRORS))
  DL_ERR_SUM=$((DL_ERR_SUM + 0))

done <<< "$DEVICE_LIST"

echo ""
echo "=== Summary ==="
echo "Devices: $TOTAL total, $ONLINE online, $OFFLINE offline"
echo "Rebooted since window: $REBOOTED/$TOTAL"
echo "Pending patches: $PENDING_SUM"
echo "Failed patches: $FAILED_SUM"
echo "Patch log issues: $PATCH_ERR_SUM"
echo "Download errors: $DL_ERR_SUM"

if [[ "$FAILED_SUM" -gt 0 ]]; then
  echo ""; echo "⚠️  ISSUES DETECTED: $FAILED_SUM failed patches"; exit 1
elif [[ "$PATCH_ERR_SUM" -gt 0 ]]; then
  echo ""; echo "⚠️  ISSUES DETECTED: $PATCH_ERR_SUM patch log issues"; exit 1
elif [[ "$PHASE" == "final" && "$REBOOTED" -lt "$TOTAL" ]]; then
  NOT_REBOOTED=$((TOTAL - REBOOTED))
  echo ""; echo "⚠️  $NOT_REBOOTED device(s) did not reboot"; exit 1
else
  echo ""; echo "✅ Maintenance progressing normally"; exit 0
fi
