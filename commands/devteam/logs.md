---
description: View execution logs, gate results, and event history.
argument-hint: [--tail N] [--level debug|info|warn|error] [--session <id>]
---

# /devteam:logs

Inspect runtime logs.

## Usage

```bash
/devteam:logs                      # last 50 events
/devteam:logs --tail 200           # last 200
/devteam:logs --level error        # only errors
/devteam:logs --session <id>      # specific session
```

## Sources

| Log | Location | Format |
|---|---|---|
| Session events | `.devteam/devteam.db` table `events` | SQLite |
| Quality gate results | `.devteam/logs/gates-<date>.log` | JSON-lines |
| Hook debug | `.devteam/logs/hooks-<date>.log` | JSON-lines |
| Abandonment attempts | `.devteam/abandonment-attempts.log` | plain text |
| Bug Council | `.devteam/bug-council-sessions/<id>/` | Markdown reports |

## Implementation

1. Query SQLite `events` table ordered by `timestamp DESC LIMIT N`
2. Filter by level/session if specified
3. Format as a readable timeline

## Output

```text
══════════════════════════════════════════
 DevTeam Logs (session-20260613-142530, last 20)
══════════════════════════════════════════

14:25:31  INFO   task_started     TASK-007
14:25:35  INFO   agent_invoked    api-developer-python
14:26:12  INFO   gate_passed      tests (142/142)
14:26:13  INFO   gate_passed      typecheck
14:26:14  ERROR  gate_failed      lint (3 errors)
14:26:14  WARN   escalation       tier: medium → high
14:26:45  INFO   agent_invoked    api-developer-python (retry)
14:27:02  INFO   gate_passed      lint
14:27:02  INFO   task_completed   TASK-007 (87s, $0.23)

══════════════════════════════════════════
```
