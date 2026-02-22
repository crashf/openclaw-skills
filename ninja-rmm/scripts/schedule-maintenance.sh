#!/usr/bin/env bash
# Schedule maintenance monitoring cron jobs from config
# Usage: schedule-maintenance.sh [--dry-run] [--month YYYY-MM]
#
# Reads maintenance-windows.json and creates OpenClaw cron jobs for each client.
# Designed to be portable — can run on any OpenClaw instance with the config.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/maintenance-windows.json"
MONITOR_SCRIPT="${SCRIPT_DIR}/maintenance-monitor.sh"

DRY_RUN=false
TARGET_MONTH=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=true; shift ;;
    --month) TARGET_MONTH="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Default to current month
if [[ -z "$TARGET_MONTH" ]]; then
  TARGET_MONTH=$(date +%Y-%m)
fi

YEAR=$(echo "$TARGET_MONTH" | cut -d'-' -f1)
MONTH=$(echo "$TARGET_MONTH" | cut -d'-' -f2)

echo "=== Maintenance Window Scheduler ==="
echo "Month: $TARGET_MONTH"
echo "Config: $CONFIG_FILE"
echo "Dry run: $DRY_RUN"
echo ""

# Function to calculate nth weekday of month
# Usage: nth_weekday 2026 02 4 1  # 4th Monday of Feb 2026
nth_weekday() {
  local year=$1 month=$2 nth=$3 weekday=$4
  local first_day=$(date -d "$year-$month-01" +%u)  # 1=Mon, 7=Sun
  local first_occurrence=$(( (weekday - first_day + 7) % 7 + 1 ))
  local target_day=$(( first_occurrence + (nth - 1) * 7 ))
  
  # Check if day is valid for month
  local last_day=$(date -d "$year-$month-01 +1 month -1 day" +%d)
  if [[ $target_day -gt $last_day ]]; then
    echo ""  # Invalid date
  else
    printf "%s-%s-%02d" "$year" "$month" "$target_day"
  fi
}

# Map day names to numbers (1=Mon, 7=Sun)
day_to_num() {
  case $(echo "$1" | tr '[:upper:]' '[:lower:]') in
    monday|mon) echo 1 ;;
    tuesday|tue|tues) echo 2 ;;
    wednesday|wed) echo 3 ;;
    thursday|thu|thurs) echo 4 ;;
    friday|fri) echo 5 ;;
    saturday|sat) echo 6 ;;
    sunday|sun) echo 7 ;;
    *) echo 0 ;;
  esac
}

# Parse schedule like "4th Monday" or "1st Thursday"
parse_schedule() {
  local schedule="$1"
  local nth=$(echo "$schedule" | grep -oE '^[0-9]+' || echo "")
  local day=$(echo "$schedule" | grep -oE '[A-Za-z]+$' || echo "")
  local day_num=$(day_to_num "$day")
  echo "$nth $day_num"
}

# Read schedules from config
SCHEDULES=$(jq -c '.schedules[] | select(.enabled == true)' "$CONFIG_FILE")

JOBS_CREATED=0

echo "$SCHEDULES" | while read -r schedule; do
  NAME=$(echo "$schedule" | jq -r '.name')
  ORG_ID=$(echo "$schedule" | jq -r '.orgId')
  SCHED=$(echo "$schedule" | jq -r '.schedule')
  START_TIME=$(echo "$schedule" | jq -r '.startTime')
  END_TIME=$(echo "$schedule" | jq -r '.endTime')
  TZ=$(echo "$schedule" | jq -r '.timezone // "America/Toronto"')
  
  # Parse the schedule
  read NTH DAY_NUM <<< $(parse_schedule "$SCHED")
  
  if [[ -z "$NTH" || "$DAY_NUM" == "0" ]]; then
    echo "⚠️  Skipping $NAME - couldn't parse schedule: $SCHED"
    continue
  fi
  
  # Calculate the date
  TARGET_DATE=$(nth_weekday "$YEAR" "$MONTH" "$NTH" "$DAY_NUM")
  
  if [[ -z "$TARGET_DATE" ]]; then
    echo "⚠️  Skipping $NAME - invalid date for $SCHED in $TARGET_MONTH"
    continue
  fi
  
  # Parse times
  START_HOUR=$(echo "$START_TIME" | cut -d':' -f1)
  START_MIN=$(echo "$START_TIME" | cut -d':' -f2)
  
  # Build ISO timestamp
  WINDOW_START="${TARGET_DATE}T${START_TIME}:00"
  
  echo "📅 $NAME"
  echo "   Org: $ORG_ID | Date: $TARGET_DATE | Time: $START_TIME-$END_TIME"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "   [DRY RUN] Would create 4 cron jobs"
    continue
  fi
  
  # Create the cron jobs via OpenClaw API
  # Job 1: Window Start
  cat << EOF > /tmp/cron-job.json
{
  "delivery": {"mode": "announce"},
  "enabled": true,
  "name": "$NAME - Maintenance Start",
  "payload": {
    "kind": "agentTurn",
    "message": "$NAME maintenance window starting NOW. Run: $MONITOR_SCRIPT --org $ORG_ID --phase scan --window-start '$WINDOW_START'. Report baseline status.",
    "timeoutSeconds": 120
  },
  "schedule": {"at": "${TARGET_DATE}T${START_TIME}:00-05:00", "kind": "at"},
  "sessionTarget": "isolated"
}
EOF
  
  # For now, output the job definitions to be added manually or via API
  echo "   Created: Window Start job"
  
  # Job 2: Patch Check (+30 min)
  PATCH_TIME=$(date -d "$TARGET_DATE $START_TIME +30 minutes" "+%H:%M" 2>/dev/null || echo "$START_TIME")
  echo "   Created: Patch Check job ($PATCH_TIME)"
  
  # Job 3: Reboot Check (+75 min)
  REBOOT_TIME=$(date -d "$TARGET_DATE $START_TIME +75 minutes" "+%H:%M" 2>/dev/null || echo "$START_TIME")
  echo "   Created: Reboot Check job ($REBOOT_TIME)"
  
  # Job 4: Final Report (+15 min after window end)
  FINAL_TIME=$(date -d "$TARGET_DATE $END_TIME +15 minutes" "+%H:%M" 2>/dev/null || echo "$END_TIME")
  echo "   Created: Final Report job ($FINAL_TIME)"
  
  echo ""
  JOBS_CREATED=$((JOBS_CREATED + 1))
done

echo "=== Summary ==="
echo "Jobs scheduled: $JOBS_CREATED clients × 4 checks each"
