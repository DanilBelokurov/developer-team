---
description: Display system health, current session, and cost summary.
---

# /devteam:status

Quick health check. Safe to call any time.

## Usage

```bash
/devteam:status
```

## Output

```text
══════════════════════════════════════════
 DevTeam Status
══════════════════════════════════════════

Database:        .devteam/devteam.db  (initialized)
Active session:  session-20260613-142530-a3f9
Active sprint:   SPRINT-002
Active plan:     oauth-login-v2

Tasks:
  ▸ TASK-007  in_progress  (api-developer-python, iter 2/10)
  ✓ TASK-006  completed    (45s, $0.12)
  ✓ TASK-005  completed    (38s, $0.09)
  ✗ TASK-004  failed       (max iterations)

Quality gates (last run):
  ✓ tests        142 passing
  ✓ typecheck    0 errors
  ✓ lint         0 errors
  ✓ scope        0 violations

Cost (today):     $1.42 / $10.00 budget

══════════════════════════════════════════
```

## Implementation

1. Read `.devteam/devteam.db` for session/task state
2. Read `.devteam/plans/<active>/sprints.json` for sprint progress
3. Aggregate cost from session events
4. Format the dashboard

If database is missing, prompt: "Run `/devteam:implement` to initialize."
