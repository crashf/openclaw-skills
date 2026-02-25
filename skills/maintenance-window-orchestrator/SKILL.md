---
name: maintenance-window-orchestrator
description: Generate, apply, and enforce recurring maintenance monitoring cron jobs from a schedule config. Use when building or managing client maintenance windows across organizations, especially for NinjaRMM/OpenClaw workflows, monthly job generation, timezone-safe scheduling, and model pinning (for example forcing all jobs to gpt-4.1).
---

# Maintenance Window Orchestrator

Use this skill to run maintenance windows as data-driven cron jobs.

## Workflow

1. Prepare a schedule config JSON (see `references/config-schema.md`).
2. Generate one-shot monthly jobs with `scripts/generate_jobs.py`.
3. Apply jobs with `scripts/apply_jobs.sh`.
4. Enforce model policy with `scripts/sync_job_models.sh`.

## Generate jobs

```bash
python3 scripts/generate_jobs.py \
  --config ../ninja-rmm/config/maintenance-windows.json \
  --month 2026-03 \
  --model github-copilot/gpt-4.1 \
  --monitor-cmd "~/.openclaw/workspace/skills/ninja-rmm/scripts/maintenance-monitor.sh" \
  --out /tmp/maintenance-jobs-2026-03.json
```

Notes:
- Supports schedules like `1st Tuesday`, `4th Monday`, `last Wednesday`.
- Uses each entry timezone and converts to UTC for cron `at` jobs.
- Generates 4 jobs per schedule: start, patch-check, reboot-check, final-report.

## Apply jobs

```bash
bash scripts/apply_jobs.sh /tmp/maintenance-jobs-2026-03.json
```

## Enforce model on existing maintenance jobs

```bash
bash scripts/sync_job_models.sh github-copilot/gpt-4.1
```

By default it targets cron names containing maintenance keywords. Provide a second argument regex to narrow scope.

## Output contract

Generated jobs use:
- `sessionTarget: isolated`
- `payload.kind: agentTurn`
- `delivery.mode: announce`
- `deleteAfterRun: true`

Adjust the generator flags if your policy changes.
