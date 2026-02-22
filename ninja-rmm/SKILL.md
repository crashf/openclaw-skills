# NinjaRMM Skill

Interact with NinjaRMM API for device monitoring, alerts, and reporting.

## Setup

Credentials are configured in `~/.openclaw/openclaw.json` under `skills.entries.ninja-rmm.env`.

## Authentication

The `scripts/auth.sh` script handles OAuth2 and caches tokens. It's called automatically by other scripts.

```bash
# Manual token fetch (if needed)
TOKEN=$(~/.openclaw/workspace/skills/ninja-rmm/scripts/auth.sh)
```

## Scripts

### status.sh — Quick overview
```bash
./scripts/status.sh              # All organizations
./scripts/status.sh --org 5      # Specific org
```
Output: device counts, alert summary, stale reboot count.

### alerts.sh — Query active alerts
```bash
./scripts/alerts.sh                        # All alerts (default limit 20)
./scripts/alerts.sh --severity critical    # Critical only
./scripts/alerts.sh --org 5 --limit 50     # Specific org
```

### devices.sh — Search/list devices
```bash
./scripts/devices.sh                       # All devices (limit 50)
./scripts/devices.sh --search "DC01"       # Search by name
./scripts/devices.sh --org 5               # Specific org
./scripts/devices.sh --offline             # Offline devices only
```

## Direct API Queries

For queries not covered by scripts, use curl with the cached token:

```bash
TOKEN=$(~/.openclaw/workspace/skills/ninja-rmm/scripts/auth.sh)
NINJA_INSTANCE="app.ninjarmm.com"

# Get device details
curl -s -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/device/{deviceId}"

# Get device software inventory
curl -s -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/device/{deviceId}/software"

# Get organization details
curl -s -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/organization/{orgId}"

# List activities (audit log)
curl -s -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/activities"
```

## Current Scope

**monitoring** (read-only) — can query devices, alerts, activities, software inventory.

To enable write operations (run scripts, reboot devices), add `management` scope to the API client in NinjaRMM Admin → API → Client App IDs.

## API Reference

- [NinjaRMM API Docs](https://app.ninjarmm.com/apidocs/)
- Base URL: `https://app.ninjarmm.com/v2/`
