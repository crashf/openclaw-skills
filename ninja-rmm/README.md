# NinjaRMM Skill

OpenClaw skill for NinjaRMM API integration.

## Features

- [ ] OAuth2 authentication with token caching
- [ ] List organizations and devices
- [ ] Query alerts and activities
- [ ] Device details and system info
- [ ] Run scripts on devices (with safety checks)
- [ ] Manage tickets/tasks

## Setup

1. In NinjaRMM: **Administration → API → Client App IDs**
2. Create a new API client with appropriate scopes
3. Add credentials to OpenClaw config (see SKILL.md)

## Usage

Once configured, the agent can use this skill to query and manage your NinjaRMM environment.

## Status

🚧 **In Development** — Authentication and read operations first, write operations later with safety gates.
