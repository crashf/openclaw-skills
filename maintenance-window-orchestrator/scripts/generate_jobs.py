#!/usr/bin/env python3
import argparse
import json
import re
from calendar import monthrange
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

ORDINALS = {"1st": 1, "2nd": 2, "3rd": 3, "4th": 4, "5th": 5, "last": -1}
WEEKDAYS = {
    "monday": 0, "mon": 0,
    "tuesday": 1, "tue": 1, "tues": 1,
    "wednesday": 2, "wed": 2,
    "thursday": 3, "thu": 3, "thurs": 3,
    "friday": 4, "fri": 4,
    "saturday": 5, "sat": 5,
    "sunday": 6, "sun": 6,
}


@dataclass
class Window:
    name: str
    org_id: str
    schedule: str
    start_time: str
    end_time: str
    timezone: str
    enabled: bool = True


def parse_schedule(expr: str):
    m = re.match(r"^\s*(\w+)\s+(\w+)\s*$", expr.lower())
    if not m:
        raise ValueError(f"Invalid schedule expression: {expr}")
    ord_token, day_token = m.groups()
    if ord_token not in ORDINALS or day_token not in WEEKDAYS:
        raise ValueError(f"Unsupported schedule expression: {expr}")
    return ORDINALS[ord_token], WEEKDAYS[day_token]


def nth_weekday(year: int, month: int, nth: int, weekday: int) -> datetime:
    if nth > 0:
        first = datetime(year, month, 1)
        offset = (weekday - first.weekday() + 7) % 7
        candidate = first + timedelta(days=offset + (nth - 1) * 7)
        if candidate.month != month:
            raise ValueError("Requested nth weekday does not exist in month")
        return candidate

    # last weekday
    last_day = monthrange(year, month)[1]
    last = datetime(year, month, last_day)
    offset = (last.weekday() - weekday + 7) % 7
    return last - timedelta(days=offset)


def parse_hhmm(value: str):
    h, m = value.split(":")
    return int(h), int(m)


def to_utc_iso(dt_local: datetime) -> str:
    return dt_local.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def build_message(name: str, org_id: str, phase: str, start_time: str, end_time: str, window_start: str, monitor_cmd: str) -> str:
    run = f"{monitor_cmd} --org {org_id} --phase {phase} --window-start '{window_start}'"
    if phase == "scan":
        return f"{name} maintenance window starting NOW ({start_time}-{end_time}). Run: {run}"
    if phase == "patch":
        return f"{name} maintenance - 30 min in. Check patch progress. Use: {run}"
    if phase == "reboot":
        return f"{name} maintenance - 75 min in. Check reboot status. Use: {run}"
    return f"{name} maintenance window ENDED. Generate final report. Use: {run}"


def make_job(name: str, when_local: datetime, model: str, message: str, timeout: int):
    return {
        "name": name,
        "schedule": {"kind": "at", "at": to_utc_iso(when_local)},
        "sessionTarget": "isolated",
        "deleteAfterRun": True,
        "payload": {
            "kind": "agentTurn",
            "message": message,
            "model": model,
            "timeoutSeconds": timeout,
        },
        "delivery": {"mode": "announce"},
        "enabled": True,
    }


def load_windows(config: Path):
    data = json.loads(config.read_text())
    defaults = data.get("defaults", {})
    windows = []
    for row in data.get("schedules", []):
        windows.append(
            Window(
                name=row["name"],
                org_id=str(row["orgId"]),
                schedule=row["schedule"],
                start_time=row["startTime"],
                end_time=row["endTime"],
                timezone=row.get("timezone", "UTC"),
                enabled=row.get("enabled", True),
            )
        )
    return windows, defaults


def main():
    p = argparse.ArgumentParser(description="Generate dynamic maintenance cron jobs")
    p.add_argument("--config", required=True, help="Path to maintenance windows JSON")
    p.add_argument("--month", required=True, help="Target month YYYY-MM")
    p.add_argument("--model", default="github-copilot/gpt-4.1")
    p.add_argument("--monitor-cmd", required=True, help="Maintenance monitor command path")
    p.add_argument("--patch-offset-min", type=int, default=None)
    p.add_argument("--reboot-offset-min", type=int, default=None)
    p.add_argument("--final-buffer-min", type=int, default=None)
    p.add_argument("--out", default="-", help="Output JSON file or - for stdout")
    args = p.parse_args()

    year, month = map(int, args.month.split("-"))
    windows, defaults = load_windows(Path(args.config))

    patch_offset = args.patch_offset_min if args.patch_offset_min is not None else int(defaults.get("patchOffsetMin", 30))
    reboot_offset = args.reboot_offset_min if args.reboot_offset_min is not None else int(defaults.get("rebootOffsetMin", 75))
    final_buffer = args.final_buffer_min if args.final_buffer_min is not None else int(defaults.get("finalBufferMin", 15))

    jobs = []
    for w in windows:
        if not w.enabled:
            continue

        nth, weekday = parse_schedule(w.schedule)
        base_date = nth_weekday(year, month, nth, weekday)
        tz = ZoneInfo(w.timezone)

        sh, sm = parse_hhmm(w.start_time)
        eh, em = parse_hhmm(w.end_time)

        start_local = base_date.replace(hour=sh, minute=sm, second=0, microsecond=0, tzinfo=tz)
        end_local = base_date.replace(hour=eh, minute=em, second=0, microsecond=0, tzinfo=tz)
        if end_local < start_local:
            end_local += timedelta(days=1)

        patch_local = start_local + timedelta(minutes=patch_offset)
        reboot_local = start_local + timedelta(minutes=reboot_offset)
        final_local = end_local + timedelta(minutes=final_buffer)

        window_start = start_local.strftime("%Y-%m-%dT%H:%M:%S")

        jobs.append(make_job(
            f"{w.name} - Maintenance Start",
            start_local,
            args.model,
            build_message(w.name, w.org_id, "scan", w.start_time, w.end_time, window_start, args.monitor_cmd),
            120,
        ))
        jobs.append(make_job(
            f"{w.name} - Patch Check",
            patch_local,
            args.model,
            build_message(w.name, w.org_id, "patch", w.start_time, w.end_time, window_start, args.monitor_cmd),
            120,
        ))
        jobs.append(make_job(
            f"{w.name} - Reboot Check",
            reboot_local,
            args.model,
            build_message(w.name, w.org_id, "reboot", w.start_time, w.end_time, window_start, args.monitor_cmd),
            120,
        ))
        jobs.append(make_job(
            f"{w.name} - Final Report",
            final_local,
            args.model,
            build_message(w.name, w.org_id, "final", w.start_time, w.end_time, window_start, args.monitor_cmd),
            180,
        ))

    payload = json.dumps(jobs, indent=2)
    if args.out == "-":
        print(payload)
    else:
        Path(args.out).write_text(payload)
        print(f"Wrote {len(jobs)} jobs to {args.out}")


if __name__ == "__main__":
    main()
