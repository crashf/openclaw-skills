#!/usr/bin/env bash
# Load cron jobs from JSON file via OpenClaw API
# Usage: load-jobs.sh <jobs.json>
# 
# This script outputs curl commands to create the jobs.
# Pipe to bash to execute: ./load-jobs.sh march-jobs.json | bash

set -euo pipefail

JOBS_FILE="${1:-}"
if [[ -z "$JOBS_FILE" || ! -f "$JOBS_FILE" ]]; then
  echo "Usage: $0 <jobs.json>" >&2
  exit 1
fi

# Read and output each job as an API call
# Note: Requires OpenClaw gateway to be running and accessible
echo "# Loading $(jq length "$JOBS_FILE") jobs from $JOBS_FILE"
echo "# Run with: $0 $JOBS_FILE | bash"
echo ""

jq -c '.[]' "$JOBS_FILE" | while read -r job; do
  NAME=$(echo "$job" | jq -r '.name')
  echo "# $NAME"
  echo "openclaw cron add '$job'"
  echo ""
done
