# NinjaRMM Skill

Interact with NinjaRMM API for device management, alerts, monitoring, and automation.

## Setup

Required environment variables (set in `~/.openclaw/openclaw.json` under `skills.entries.ninja-rmm.env`):

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

## Authentication

NinjaRMM uses OAuth2 client credentials flow:

```bash
# Get access token
curl -X POST "https://${NINJA_INSTANCE}/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=${NINJA_CLIENT_ID}&client_secret=${NINJA_CLIENT_SECRET}&scope=monitoring management"
```

Use the returned `access_token` in subsequent API calls as `Authorization: Bearer <token>`.

## Common Operations

### List Organizations
```bash
curl -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/organizations"
```

### List Devices
```bash
curl -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/devices"
```

### Get Device Details
```bash
curl -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/device/{deviceId}"
```

### Get Active Alerts
```bash
curl -H "Authorization: Bearer $TOKEN" "https://${NINJA_INSTANCE}/v2/alerts"
```

### Run Script on Device
```bash
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "https://${NINJA_INSTANCE}/v2/device/{deviceId}/script/run" \
  -d '{"scriptId": 123, "parameters": {}}'
```

## Scripts

- `scripts/auth.sh` — Get OAuth token and cache it
- `scripts/devices.sh` — List/search devices
- `scripts/alerts.sh` — Query and manage alerts

## Safety

⚠️ **NinjaRMM has significant blast radius.** Before running any write/execute operations:
- Confirm the target device(s) explicitly
- Use `--dry-run` flags where available
- Never bulk-execute scripts without human approval

## API Reference

- [NinjaRMM API Docs](https://app.ninjarmm.com/apidocs/)
- Base URL: `https://{instance}/v2/`
