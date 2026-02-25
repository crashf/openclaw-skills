#!/usr/bin/env bash
set -euo pipefail

JOBS_FILE="${1:-}"
if [[ -z "$JOBS_FILE" || ! -f "$JOBS_FILE" ]]; then
  echo "Usage: $0 <jobs.json>" >&2
  exit 1
fi

count=$(jq length "$JOBS_FILE")
echo "Applying $count jobs from $JOBS_FILE"

jq -c '.[]' "$JOBS_FILE" | while read -r job; do
  name=$(echo "$job" | jq -r '.name')
  echo "+ $name"
  openclaw cron add "$job" >/dev/null
 done

echo "Done"
