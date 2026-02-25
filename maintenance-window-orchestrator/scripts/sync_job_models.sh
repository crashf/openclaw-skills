#!/usr/bin/env bash
set -euo pipefail

MODEL="${1:-github-copilot/gpt-4.1}"
NAME_REGEX="${2:-Maintenance|Patch Check|Reboot Check|Final Report}"

tmp=$(mktemp)
openclaw cron list > "$tmp"

# Parse IDs + names from tabular output
awk 'NR>1 {id=$1; $1=""; name=$0; sub(/^ +/, "", name); print id "\t" name}' "$tmp" |
while IFS=$'\t' read -r id name; do
  if echo "$name" | grep -Eiq "$NAME_REGEX"; then
    echo "Updating $id :: $name -> $MODEL"
    openclaw cron edit "$id" --model "$MODEL" >/dev/null
  fi
done

rm -f "$tmp"
echo "Model sync complete"
