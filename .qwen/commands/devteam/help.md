---
description: Show all commands and usage examples.
argument-hint: [<command>]
---

# /devteam:help

List all DevTeam commands with usage.

## Usage

```bash
/devteam:help             # all commands
/devteam:help implement   # detailed help for one command
```

## Commands

### Planning & Execution

| Command | Purpose |
|---|---|
| `/devteam:plan` | Interview-driven planning; produces PRD, task graph, sprints |
| `/devteam:implement` | Execute plans, sprints, tasks, or ad-hoc work |
| `/devteam:bug` | Diagnose and fix bugs (with optional Bug Council) |
| `/devteam:issue` | Fix a GitHub issue end-to-end |
| `/devteam:issue-new` | Create a new GitHub issue from a description |

### Quality & Review

| Command | Purpose |
|---|---|
| `/devteam:review` | Cross-agent code review |
| `/devteam:test` | Test coordination and execution |
| `/devteam:design` | Design system generation and validation |
| `/devteam:design-drift` | Detect design system drift |

### Observability

| Command | Purpose |
|---|---|
| `/devteam:status` | System health, session, cost dashboard |
| `/devteam:list` | List all plans, sprints, tasks |
| `/devteam:logs` | View runtime logs |
| `/devteam:config` | View and modify configuration |
| `/devteam:reset` | Recover from stuck sessions |

### Worktrees

| Command | Purpose |
|---|---|
| `/devteam:worktree` | Inspect, list, clean, merge parallel worktrees |

## Quick Examples

```bash
# Full planning → execution flow
/devteam:plan --feature "Add OAuth"
/devteam:implement --sprint 1

# Quick fix
/devteam:bug "Race in checkout" --council

# Investigate stuck session
/devteam:status
/devteam:logs --level error
/devteam:reset
/devteam:implement   # resume
```

## Getting More Help

- `docs/GETTING_STARTED.md` — first-time setup
- `docs/TROUBLESHOOTING.md` — common issues
- `docs/MIGRATION_FROM_CLAUDE.md` — coming from Claude Code
