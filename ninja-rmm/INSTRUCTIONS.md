# NinjaRMM Maintenance Monitoring Bot

## Overview

This bot monitors monthly server maintenance windows for Pund-IT clients using NinjaRMM. It tracks patch installation and reboot status during scheduled windows, notifying via Telegram when each phase completes or if issues occur.

## Quick Start

### 1. Set Up NinjaRMM Credentials

Add to `~/.openclaw/openclaw.json`:

```json
{
  "skills": {
    "entries": {
      "ninja-rmm": {
        "env": {
          "NINJA_CLIENT_ID": "your-client-id",
          "NINJA_CLIENT_SECRET": "your-client-secret",
          "NINJA_INSTANCE": "app.ninjarmm.com"
        }
      }
    }
  }
}
```

Get credentials from NinjaRMM: **Administration → API → Client App IDs**

### 2. Link the Skill

```bash
mkdir -p ~/.openclaw/workspace/skills
ln -sf /path/to/openclaw-skills/ninja-rmm ~/.openclaw/workspace/skills/ninja-rmm
```

### 3. Generate Monthly Jobs

```bash
cd ~/.openclaw/workspace/skills/ninja-rmm/scripts

# Generate jobs for a specific month (uses GPT-4o by default)
python3 generate-cron-jobs.py --month 2026-04 --output ../config/april-2026-jobs.json

# Use a different model
python3 generate-cron-jobs.py --month 2026-04 --model sonnet

# View the schedule
cat ../config/april-2026-jobs.json | jq -r '.[] | select(.name | contains("Start")) | "\(.schedule.at): \(.name)"' | sort
```

### 4. Load Jobs into OpenClaw

Jobs can be loaded via the OpenClaw cron API. From a chat session, ask the bot to create cron jobs from the generated JSON file.

### 5. Mandatory Cron Coverage Check (Do this every month)

Before each month starts (or immediately after schedule changes):

1. Generate jobs for the month from `config/maintenance-windows.json`.
2. Load/apply those jobs into OpenClaw.
3. Verify jobs exist with `openclaw cron list`.
4. Confirm each enabled client has maintenance jobs present for that month (minimum start + final; preferred full phase set).
5. If any window is missing, generate/apply again before the window begins.

This is required so maintenance monitoring always kicks off automatically without manual intervention.

---

## File Structure

```
ninja-rmm/
├── config/
│   ├── maintenance-windows.json    # Client schedules (source of truth)
│   └── march-2026-jobs.json        # Pre-generated job definitions
├── scripts/
│   ├── auth.sh                     # OAuth2 token fetch with caching
│   ├── status.sh                   # Quick status overview
│   ├── alerts.sh                   # Query active alerts
│   ├── devices.sh                  # List/search devices
│   ├── maintenance-monitor.sh      # Main monitoring script
│   ├── generate-cron-jobs.py       # Generate cron jobs from config
│   └── load-jobs.sh                # Helper to output job creation commands
├── SKILL.md                        # Agent instructions
└── README.md                       # Human documentation
```

---

## How Maintenance Monitoring Works

### Maintenance Windows

Each client has a monthly maintenance window defined in `config/maintenance-windows.json`:

```json
{
  "name": "Primespec Distribution Inc.",
  "orgId": 35,
  "schedule": "4th Monday",
  "startTime": "17:00",
  "endTime": "19:00",
  "timezone": "America/Toronto",
  "enabled": true
}
```

### Monitoring Phases

During each window, the bot runs 4 checks:

1. **Window Start (T+0)** — Baseline status: which servers are online, pending patches
2. **Patch Check (T+30min)** — Are patches installing? Any failures?
3. **Reboot Check (T+75min)** — Which servers have rebooted?
4. **Final Report (T+window+15min)** — Summary: success/failures, action items

### Required Ops Policy (Wayne)

These are mandatory for every maintenance window:

1. **Automatic kickoff via cron is required:** ensure a cron-driven maintenance start job exists for every enabled window (no manual-only starts).
2. **30 minutes before window end:** run a detailed monitor check and send device-level results (online/offline, rebooted count, pending/failed, patch-log issues, post-reboot-scan flags).
3. **Reboot verification is required:** explicitly confirm whether each expected server rebooted during the window. If any did not reboot, flag as an issue.
4. **Error capture for ticketing:** any patch failures, patch-log issues, download errors, or post-reboot-scan-required flags must be called out clearly so a follow-up ticket can be created.
5. **No generic-only updates:** do not rely only on high-level cron completion text when detailed monitor output is available.

### Required Per-Window Report Format (Exact deliverable)

For **each machine involved** in the maintenance window, send a report with this structure:

- **Device:** <hostname> (online/offline)
- **Reboots during window:** Yes/No (+ count and approximate times)
- **Patch status outcome:**
  - Pending patches: <count>
  - Failed patches: <count>
  - Patch-management failure events: <count + short reason>
  - Post-reboot scan required: Yes/No
- **Issues to ticket:**
  1. <issue 1>
  2. <issue 2>
  3. <issue 3>

Rules:
- If there are no issues, explicitly state **"No ticketable issues detected."**
- If a reboot was required but did not happen, always include a ticket item.
- Include significant activity events that justify conclusions (e.g., pending reboot block, scan completed, reboot detected).
- Deliver this report at minimum at the **30-min-before-end check** and in the **final summary**.

### What Gets Monitored

- **Servers only** (WINDOWS_SERVER class) — not workstations
- Patch status: PENDING → INSTALLED or FAILED
- Reboot confirmation: `system.lastBoot` vs window start time
- Device online/offline status

---

## Scripts Reference

### maintenance-monitor.sh

The main monitoring script. Queries NinjaRMM for server status during maintenance.

```bash
# Basic usage
./maintenance-monitor.sh --org 35 --phase scan --window-start '2026-02-23T17:00:00'

# Phases: scan, patch, reboot, final
```

**Output includes:**
- Per-device status (online/offline, patched, rebooted)
- Pending/failed patch counts
- Summary with issues flagged

### generate-cron-jobs.py

Generates OpenClaw cron job definitions from the maintenance config.

```bash
# Generate for a specific month (default model: github-copilot/gpt-4o)
python3 generate-cron-jobs.py --month 2026-04

# Save to file
python3 generate-cron-jobs.py --month 2026-04 --output ../config/april-2026-jobs.json

# Use a different model (e.g., sonnet for Claude)
python3 generate-cron-jobs.py --month 2026-04 --model sonnet
```

**Default model:** `github-copilot/gpt-4o` — cost-effective for API calls + reporting tasks.

### status.sh / alerts.sh / devices.sh

Quick query scripts for ad-hoc checks:

```bash
# Overall status
./status.sh

# Status for specific org
./status.sh --org 35

# Active alerts
./alerts.sh --severity critical

# Search devices
./devices.sh --search "DC01"
./devices.sh --org 35 --offline
```

---

## Client Schedule (17 Clients)

| Client | Schedule | Time | Org ID |
|--------|----------|------|--------|
| 2287685 Ontario Inc | 1st Thursday | 8:30am | 3 |
| Altanic Transportation | 3rd Tuesday | 6pm | 7 |
| BA Folding Cartons | 3rd Friday | 6pm | 14 |
| Breadner Trailers | 1st Friday | 6pm | 8 |
| Building Knowledge | 3rd Tuesday | 7pm | 17 |
| Community Support Connections | 1st Tuesday | 6pm | 10 |
| Delta Elevator | 3rd Saturday | 8pm-midnight | 20 |
| Gemstar Group | 1st Thursday | 7-8pm | 22 |
| Magic Lite | 3rd Thursday | 6-8pm | 26 |
| Primespec Distribution | 4th Monday | 5-7pm | 35 |
| Pund-IT Corporate | 1st Wednesday | 5-7pm | 2 |
| SAF Drives | 3rd Wednesday | 6pm | 60 |
| Steed Standard Transport | 4th Monday | 5:30pm | 36 |
| The Beat Goes On | 4th Wednesday | 7-8pm | 37 |
| Uni-Spray Systems | 4th Thursday | 6:30pm | 38 |
| Wilride Transport | 4th Thursday | 7-9pm | 39 |
| Woeller Group | 2nd Tuesday | 5:30-7:30pm | 52 |

**Clients needing time confirmation:** ISD, JTS Mechanical, M Machel, McCutchen & Pearce, OnePoint Realtors, Pfenning's, Think Green, Yardistry

---

## Adding a New Client

1. Add entry to `config/maintenance-windows.json`
2. Re-run `generate-cron-jobs.py` for affected month(s)
3. Load new jobs via cron API

---

## Troubleshooting

### Auth Fails
- Check credentials in `~/.openclaw/openclaw.json`
- Verify API client has `monitoring` scope in NinjaRMM admin
- Token cache: `~/.cache/ninja-rmm-token.json`

### No Servers Found
- Script filters for `WINDOWS_SERVER` only
- Check org ID matches NinjaRMM

### Jobs Not Running
- Verify cron jobs are enabled: `cron list`
- Check OpenClaw gateway is running

---

## API Scope

Current scope: **monitoring** (read-only)

To enable write operations (run scripts, reboot devices), add `management` scope to the API client in NinjaRMM.

---

## Source

- **GitHub:** https://github.com/crashf/openclaw-skills
- **NinjaRMM API Docs:** https://app.ninjarmm.com/apidocs/
