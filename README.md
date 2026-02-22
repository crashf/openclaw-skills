# OpenClaw Skills

Custom OpenClaw skills for Pund-IT automation workflows.

## Skills

| Skill | Description | Status |
|-------|-------------|--------|
| [ninja-rmm](./ninja-rmm/) | NinjaRMM API integration for device management, alerts, and scripting | 🚧 In Progress |

## Installation

To use a skill locally, symlink or copy it to your OpenClaw workspace skills folder:

```bash
# Example: link ninja-rmm skill
ln -s /path/to/openclaw-skills/ninja-rmm ~/.openclaw/workspace/skills/ninja-rmm
```

Or install via ClawHub once published.

## Structure

Each skill folder contains:
- `SKILL.md` — Instructions for the agent
- `scripts/` — Helper scripts (bash, python, etc.)
- `README.md` — Human documentation

## License

Private — Pund-IT internal use.
