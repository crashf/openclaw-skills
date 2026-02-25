# NinjaRMM Maintenance Monitor (n8n)

Use this n8n flow to monitor maintenance windows in read-only mode and send alerts with device links when reboots occur and post-reboot scans/patch issues are detected in activity logs.

## What it does
- Runs on a schedule during maintenance windows (cron).
- Fetches Ninja activity logs per Windows server in a given org.
- Detects:
  - `SYSTEM_REBOOTED` events within the window
  - Patch issues (`FAILED|ERROR` or download failure keywords)
  - "post reboot scan is required" messages
- Sends a notification with device name, device ID, and a console link for you to run scans/reboots manually.
- De-dupes alerts per device per window (via n8n workflow static data).

## Inputs to configure
- **NINJA_CLIENT_ID / NINJA_CLIENT_SECRET**: from Ninja API client (read-only scope).
- **NINJA_INSTANCE**: e.g., `pundit.rmmservice.com`.
- **ORG_ID**: target org.
- **WINDOW_START** / **WINDOW_END**: ISO timestamps for the current window (or compute from cron context).
- **LINK_BASE**: e.g., `https://pundit.rmmservice.com/#/deviceDashboard`.
- **NOTIFY_EMAIL** (or Slack/Telegram): destination for alerts.

## How to use
1) Import `workflow.json` into n8n.
2) Open the **Set Config** node and fill in:
   - `NINJA_CLIENT_ID`
   - `NINJA_CLIENT_SECRET`
   - `NINJA_INSTANCE`
   - `ORG_ID`
   - `WINDOW_START` and `WINDOW_END` (update per window via cron or a parent workflow)
   - `LINK_BASE`
   - `NOTIFY_EMAIL` (or adapt the notifier node to Slack/Telegram)
3) Enable the Cron trigger for your window cadence (e.g., every 10–15 minutes during the window).
4) Test run once; verify the Email/Notifier node receives rows when a reboot + post-reboot scan/patch issues are present.

## Behavior details
- Devices: filters to `WINDOWS_SERVER` class via the Ninja devices endpoint.
- Activity window: filters `activityTime` >= `WINDOW_START`.
- Reboot detect: `SYSTEM_REBOOTED` statusCode or message containing `System rebooted`.
- Patch issues: activityResult `FAILURE`, statusCode matching `FAILED|ERROR`, or messages containing `download error|failed|blocked`.
- Post-reboot scan: message contains `post reboot scan is required`.
- De-dupe: stores `(deviceId, windowStart)` keys in workflow static data to avoid duplicate alerts.

## Outputs
- One notification per newly detected device condition with fields:
  - deviceName, deviceId
  - rebooted: true/false
  - patchIssuesCount
  - postRebootScanRequired: true/false
  - link: `${LINK_BASE}/${deviceId}/overview`

## Notes
- Keep this workflow read-only; do not add reboot/scan actions.
- For multiple orgs/windows, clone the workflow or drive it from a parent scheduler that sets config vars before executing this workflow.
