#!/usr/bin/env python3
"""
Generate maintenance monitoring cron jobs from config.
Outputs JSON that can be used with OpenClaw cron API.

Usage: python3 generate-cron-jobs.py [--month YYYY-MM] [--output jobs.json]
"""

import json
import sys
from datetime import datetime, timedelta
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
CONFIG_FILE = SCRIPT_DIR.parent / "config" / "maintenance-windows.json"
MONITOR_SCRIPT = "~/.openclaw/workspace/skills/ninja-rmm/scripts/maintenance-monitor.sh"

def nth_weekday(year: int, month: int, nth: int, weekday: int) -> datetime | None:
    """
    Calculate the nth occurrence of a weekday in a month.
    weekday: 0=Monday, 6=Sunday
    """
    from calendar import monthrange
    
    first_day = datetime(year, month, 1)
    first_weekday = first_day.weekday()
    
    # Days until first occurrence of target weekday
    days_until = (weekday - first_weekday + 7) % 7
    first_occurrence = first_day + timedelta(days=days_until)
    
    # Add weeks to get nth occurrence
    target = first_occurrence + timedelta(weeks=nth - 1)
    
    # Check if still in same month
    if target.month != month:
        return None
    return target

def parse_schedule(schedule: str) -> tuple[int, int] | None:
    """Parse '4th Monday' into (4, 0) where 0=Monday"""
    day_map = {
        'monday': 0, 'mon': 0,
        'tuesday': 1, 'tue': 1, 'tues': 1,
        'wednesday': 2, 'wed': 2,
        'thursday': 3, 'thu': 3, 'thurs': 3,
        'friday': 4, 'fri': 4,
        'saturday': 5, 'sat': 5,
        'sunday': 6, 'sun': 6,
    }
    
    parts = schedule.lower().split()
    if len(parts) != 2:
        return None
    
    nth_str, day_str = parts
    nth = int(''.join(filter(str.isdigit, nth_str)))
    weekday = day_map.get(day_str)
    
    if weekday is None:
        return None
    return (nth, weekday)

def generate_jobs(year: int, month: int):
    """Generate cron job definitions for a month"""
    
    with open(CONFIG_FILE) as f:
        config = json.load(f)
    
    jobs = []
    
    for sched in config.get('schedules', []):
        if not sched.get('enabled', True):
            continue
        
        name = sched['name']
        org_id = sched['orgId']
        schedule = sched['schedule']
        start_time = sched['startTime']
        end_time = sched['endTime']
        
        parsed = parse_schedule(schedule)
        if not parsed:
            print(f"Warning: Couldn't parse schedule '{schedule}' for {name}", file=sys.stderr)
            continue
        
        nth, weekday = parsed
        target_date = nth_weekday(year, month, nth, weekday)
        
        if not target_date:
            print(f"Warning: {schedule} doesn't exist in {year}-{month:02d} for {name}", file=sys.stderr)
            continue
        
        date_str = target_date.strftime("%Y-%m-%d")
        window_start = f"{date_str}T{start_time}:00"
        
        # Parse times for offset calculations
        start_h, start_m = map(int, start_time.split(':'))
        end_h, end_m = map(int, end_time.split(':'))
        
        start_dt = target_date.replace(hour=start_h, minute=start_m)
        end_dt = target_date.replace(hour=end_h, minute=end_m)
        
        # Job timings
        patch_check = start_dt + timedelta(minutes=30)
        reboot_check = start_dt + timedelta(minutes=75)
        final_report = end_dt + timedelta(minutes=15)
        
        # Job 1: Window Start
        jobs.append({
            "name": f"{name} - Maintenance Start",
            "orgId": org_id,
            "schedule": {"kind": "at", "at": f"{date_str}T{start_time}:00-05:00"},
            "sessionTarget": "isolated",
            "payload": {
                "kind": "agentTurn",
                "message": f"{name} maintenance window starting NOW ({start_time}-{end_time} EST). Run the NinjaRMM maintenance monitor for org {org_id} and report baseline status. Use: {MONITOR_SCRIPT} --org {org_id} --phase scan --window-start '{window_start}'",
                "timeoutSeconds": 120
            },
            "delivery": {"mode": "announce"},
            "enabled": True
        })
        
        # Job 2: Patch Check
        jobs.append({
            "name": f"{name} - Patch Check",
            "orgId": org_id,
            "schedule": {"kind": "at", "at": patch_check.strftime("%Y-%m-%dT%H:%M:00-05:00")},
            "sessionTarget": "isolated",
            "payload": {
                "kind": "agentTurn",
                "message": f"{name} maintenance - 30 min in. Check patch progress for org {org_id}. Use: {MONITOR_SCRIPT} --org {org_id} --phase patch --window-start '{window_start}'. Report any issues.",
                "timeoutSeconds": 120
            },
            "delivery": {"mode": "announce"},
            "enabled": True
        })
        
        # Job 3: Reboot Check
        jobs.append({
            "name": f"{name} - Reboot Check",
            "orgId": org_id,
            "schedule": {"kind": "at", "at": reboot_check.strftime("%Y-%m-%dT%H:%M:00-05:00")},
            "sessionTarget": "isolated",
            "payload": {
                "kind": "agentTurn",
                "message": f"{name} maintenance - 75 min in. Check reboot status for org {org_id}. Use: {MONITOR_SCRIPT} --org {org_id} --phase reboot --window-start '{window_start}'. Report which servers rebooted.",
                "timeoutSeconds": 120
            },
            "delivery": {"mode": "announce"},
            "enabled": True
        })
        
        # Job 4: Final Report
        jobs.append({
            "name": f"{name} - Final Report",
            "orgId": org_id,
            "schedule": {"kind": "at", "at": final_report.strftime("%Y-%m-%dT%H:%M:00-05:00")},
            "sessionTarget": "isolated",
            "payload": {
                "kind": "agentTurn",
                "message": f"{name} maintenance window ENDED. Generate final report for org {org_id}. Use: {MONITOR_SCRIPT} --org {org_id} --phase final --window-start '{window_start}'. Summarize: servers rebooted, failures, pending patches. Flag any issues.",
                "timeoutSeconds": 180
            },
            "delivery": {"mode": "announce"},
            "enabled": True
        })
    
    return jobs

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser()
    parser.add_argument("--month", default=datetime.now().strftime("%Y-%m"))
    parser.add_argument("--output", default="-")
    args = parser.parse_args()
    
    year, month = map(int, args.month.split("-"))
    jobs = generate_jobs(year, month)
    
    output = json.dumps(jobs, indent=2)
    
    if args.output == "-":
        print(output)
    else:
        with open(args.output, "w") as f:
            f.write(output)
        print(f"Wrote {len(jobs)} jobs to {args.output}", file=sys.stderr)
