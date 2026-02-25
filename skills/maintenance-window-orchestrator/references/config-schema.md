# Config schema

Expected JSON shape:

```json
{
  "schedules": [
    {
      "name": "Client Name",
      "orgId": 37,
      "schedule": "4th Wednesday",
      "startTime": "19:00",
      "endTime": "20:00",
      "timezone": "America/Toronto",
      "enabled": true
    }
  ]
}
```

Fields:
- `name` (string): Display name used in cron job name and report prompts.
- `orgId` (number|string): Organization id passed to monitor command.
- `schedule` (string): `Nth Weekday` or `last Weekday`.
- `startTime` / `endTime` (string): `HH:MM` (24-hour).
- `timezone` (IANA tz): e.g. `America/Toronto`.
- `enabled` (bool): optional; defaults to true.

Optional top-level:
- `defaults.patchOffsetMin` (int, default 30)
- `defaults.rebootOffsetMin` (int, default 75)
- `defaults.finalBufferMin` (int, default 15)
