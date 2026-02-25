# NinjaRMM Skill

Interact with NinjaRMM API for device monitoring, alerts, and reporting.

## Setup

Credentials are configured in `~/.openclaw/openclaw.json` under `skills.entries.ninja-rmm.env` (API keys must NEVER be committed to git).

## Authentication

The `scripts/auth.sh` script handles OAuth2 and caches tokens. It's called automatically by other scripts.

```
# Manual token fetch (if needed)
TOKEN=$(~/.openclaw/workspace/skills/ninja-rmm/scripts/auth.sh)
```

## Troubleshooting

**Credential errors are the most common cause of API failures.**
- If the `client_id` and `client_secret` are incorrect, the auth script won't return a token, leading to 'invalid header' or HTTP errors.
- Always use client credentials that are activated and properly scoped for your instance.
- If authentication fails repeatedly, try alternate credentials before debugging endpoint or code.

Lesson learned: Valid credentials are step zero. Swapping to working ones fixed authentication and endpoint access immediately.

## Shared Library

`scripts/lib.sh` provides shared functions used by all scripts:
- **Pagination** — `ninja_fetch_all_devices` fetches ALL devices across pages (no more 50-device limit)
- **Org name resolution** — `ninja_org_name` and `ninja_fetch_orgs` map org IDs to names (cached 1hr)
- **Device class helpers** — `is_server_class`, `is_workstation_class` for filtering

## Scripts

### status.sh — Quick overview
```
./scripts/status.sh                # All organizations
./scripts/status.sh --org 5        # Specific org
./scripts/status.sh --servers      # Servers only
./scripts/status.sh --verbose      # Breakdown by type + stale reboot details
```
Output: device counts, offline servers list, alert summary, stale reboot count.

### alerts.sh — Query active alerts
```
./scripts/alerts.sh                        # All alerts (default limit 50, with org names)
./scripts/alerts.sh --severity critical    # Critical only
./scripts/alerts.sh --org 5 --limit 100   # Specific org
./scripts/alerts.sh --no-org              # Hide org names (faster)
```

### devices.sh — Search/list devices
```
./scripts/devices.sh                       # All devices (with org names)
./scripts/devices.sh --search "DC01"       # Search by name
./scripts/devices.sh --org 5               # Specific org
./scripts/devices.sh --offline             # Offline devices only
./scripts/devices.sh --servers             # Servers only (SERVER, VM_HOST, CLOUD_MONITOR)
./scripts/devices.sh --offline --servers   # Offline servers only
./scripts/devices.sh --workstations        # Workstations only
./scripts/devices.sh --network             # Network devices only (switches, WAPs, etc.)
./scripts/devices.sh --limit 20            # Limit results
```

### maintenance-monitor.sh — Monitor maintenance windows
```
./scripts/maintenance-monitor.sh --org 5 --phase scan
./scripts/maintenance-monitor.sh --org 5 --phase patch --window-start "2026-02-23T17:00:00"
./scripts/maintenance-monitor.sh --org 5 --phase final --window-start "2026-02-23T17:00:00"
```

## Direct API Queries

For queries not covered by scripts, use curl with the cached token:

```
TOKEN=$(~/.openclaw/workspace/skills/ninja-rmm/scripts/auth.sh)
NINJA_INSTANCE="app.ninjarmm.com"

# Get device details
curl -s -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/device/{deviceId}"

# Get device software inventory
curl -s -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/device/{deviceId}/software"

# Get organization details
curl -s -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/organizations/{orgId}"

# List activities (audit log)
curl -s -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/activities"
```

## Current Scope

**monitoring** (read-only) — can query devices, alerts, activities, software inventory.

To enable write operations (run scripts, reboot devices), add `management` scope to the API client in NinjaRMM Admin → API → Client App IDs.

## API Reference

- [NinjaRMM API Docs](https://app.ninjarmm.com/apidocs/)
- Base URL: `https://app.ninjarmm.com/v2/`
