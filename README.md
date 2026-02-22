# OpenClaw Skills — Pund-IT

Custom OpenClaw skills for Pund-IT MSP automation workflows.

## Skills

| Skill | Description | Status |
|-------|-------------|--------|
| [ninja-rmm](./ninja-rmm/) | NinjaRMM API integration — maintenance monitoring, alerts, device queries | ✅ Active |

## Quick Start

### 1. Clone this repo
```bash
git clone https://github.com/crashf/openclaw-skills.git
cd openclaw-skills
```

### 2. Link skills to OpenClaw workspace
```bash
mkdir -p ~/.openclaw/workspace/skills
ln -sf $(pwd)/ninja-rmm ~/.openclaw/workspace/skills/ninja-rmm
```

### 3. Configure credentials
See each skill's `INSTRUCTIONS.md` for setup details.

## For New Bots

If you're a new OpenClaw instance taking over this automation:

1. **Read `ninja-rmm/INSTRUCTIONS.md`** — complete setup guide
2. **Set credentials** in `~/.openclaw/openclaw.json`
3. **Generate monthly jobs** with `scripts/generate-cron-jobs.py`
4. **Load jobs** via OpenClaw cron API

The `SKILL.md` files are for agent consumption (read during task execution).
The `INSTRUCTIONS.md` files are comprehensive human/bot onboarding docs.

## Structure

```
openclaw-skills/
├── README.md                 # This file
└── ninja-rmm/
    ├── SKILL.md              # Agent instructions (loaded by OpenClaw)
    ├── INSTRUCTIONS.md       # Full setup & reference guide
    ├── README.md             # Human summary
    ├── config/
    │   ├── maintenance-windows.json   # Client schedules
    │   └── march-2026-jobs.json       # Pre-generated jobs
    └── scripts/
        ├── auth.sh                    # OAuth2 authentication
        ├── maintenance-monitor.sh     # Main monitoring script
        ├── generate-cron-jobs.py      # Job generator
        └── ...
```

## License

Private — Pund-IT internal use.
